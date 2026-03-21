import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var currentAccount: Account?
    var savedAccounts: [Account]
    var preferences: Preferences
    var loginFlow: LoginFlowState
    var refreshing: Bool
    var statusMessage: String?
    var errorMessage: String?

    nonisolated(unsafe) private let accountStore: AccountStore
    nonisolated(unsafe) private let legacyKeychainService: any KeychainStoring
    private let appServer: CodexAppServer
    nonisolated(unsafe) private let usageProbe: UsageProbe
    nonisolated(unsafe) private let authService: AuthService
    private var accountCacheByID: [String: Account] = [:]
    private var pendingLoginId: String?
    private var pendingRepairAccountID: String?
    private var dashboardLoading = false
    private var dashboardLoaded = false
    private var refreshingAccountIDs: Set<String> = []
    private var autoRefreshTasks: [String: Task<Void, Never>] = [:]
    private var autoRefreshTargets: [String: Date] = [:]
    private var autoRefreshFiredTargets: [String: Date] = [:]
    private var legacyKeychainMigrationCompleted = false

    init(
        accountStore: AccountStore = try! AccountStore(),
        legacyKeychainService: any KeychainStoring = KeychainService(),
        appServer: CodexAppServer = CodexAppServer(),
        usageProbe: UsageProbe = UsageProbe(),
        authService: AuthService = AuthService()
    ) {
        self.accountStore = accountStore
        self.legacyKeychainService = legacyKeychainService
        self.appServer = appServer
        self.usageProbe = usageProbe
        self.authService = authService
        self.pendingLoginId = nil
        self.pendingRepairAccountID = nil

        self.currentAccount = nil
        self.savedAccounts = []
        self.preferences = Preferences()
        self.loginFlow = LoginFlowState.empty()
        self.refreshing = false
        self.statusMessage = nil
        self.errorMessage = nil

        Strings.languageProvider = { [weak self] in
            self?.preferences.language ?? Preferences.defaultLanguage
        }

        appServer.setNotificationHandler { [weak self] notification in
            Task { @MainActor in
                self?.handle(notification: notification)
            }
        }

    }

    func loadDashboard() async {
        guard !dashboardLoaded else { return }
        await loadDashboard(force: false)
    }

    func forceReloadDashboard() async {
        dashboardLoaded = false
        await loadDashboard(force: true)
    }

    func isRefreshing(accountID: String?) -> Bool {
        guard let accountID, !accountID.isEmpty else { return false }
        return refreshingAccountIDs.contains(accountID)
    }

    func refreshingAccountLabel() -> String? {
        guard !refreshingAccountIDs.isEmpty else { return nil }

        if let current = currentAccount, refreshingAccountIDs.contains(current.id) {
            return visibleEmail(for: current)
        }

        if let saved = savedAccounts.first(where: { refreshingAccountIDs.contains($0.id) }) {
            return visibleEmail(for: saved)
        }

        if let cached = accountCacheByID.values.first(where: { refreshingAccountIDs.contains($0.id) }) {
            return visibleEmail(for: cached)
        }

        return Strings.L("当前账号", en: "Current account")
    }

    func showStatus(_ message: String) {
        errorMessage = nil
        statusMessage = message

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.statusMessage == message else { return }
            self.statusMessage = nil
        }
    }

    func loadDashboard(force: Bool) async {
        guard !dashboardLoading else { return }
        if !force, dashboardLoaded { return }

        dashboardLoading = true
        defer {
            dashboardLoading = false
            dashboardLoaded = true
        }
        errorMessage = nil
        do {
            // Step 1: Load cache immediately — user sees data right away
            let prefs = try accountStore.loadPreferences()
            preferences = prefs
            applyPreferencesSideEffects()

            let currentAuthBlob = try? accountStore.readAuthFile()
            let registry = try migrateLegacyKeychainAccountsIfNeeded(try accountStore.loadRegistry())
            let normalizedRegistry = normalizeAccountsFromStoredAuth(registry)
            let repairedRegistry = repairAccountsWithCurrentAuthIfPossible(normalizedRegistry.accounts, currentAuthBlob: currentAuthBlob)
            if normalizedRegistry.changed || repairedRegistry.changed {
                try accountStore.saveRegistry(repairedRegistry.accounts)
            }

            accountCacheByID = repairedRegistry.accounts.reduce(into: [:]) { cache, account in
                cache[account.id] = account
            }
            savedAccounts = applyMasking(to: repairedRegistry.accounts)
            NSLog("[CXSwitch] loadDashboard: cache loaded, %d accounts", repairedRegistry.accounts.count)

            // Show cached current account instantly
            if let cached = repairedRegistry.accounts.first(where: { $0.isCurrent }) {
                currentAccount = applyMasking(to: cached)
                NSLog("[CXSwitch] loadDashboard: cached current = %@", cached.email)
            }
            rescheduleAutoRefreshTasks()

            // Step 2: Background — start app-server and fetch live data
            NSLog("[CXSwitch] loadDashboard: starting app server...")
            try await startAppServerIfNeeded()
            try await appServer.initialize()

            let current = await loadCurrentAccountForDashboard()
            if let current {
                currentAccount = current
                NSLog("[CXSwitch] loadDashboard: live current = %@", current.email)
                await persistAccount(current)
            } else if currentAccount == nil {
                NSLog("[CXSwitch] loadDashboard: no current account")
            }

        } catch {
            NSLog("[CXSwitch] loadDashboard error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(to account: Account) async {
        errorMessage = nil
        statusMessage = nil
        refreshing = true
        defer { refreshing = false }

        do {
            let resolvedAuth = try resolveAuthBlob(for: account)

            guard let resolvedAuth else {
                await beginLoginFlow(repairTargetID: account.id)
                return
            }

            try accountStore.writeAuthFile(resolvedAuth.blob)
            try await appServer.restartAndInitialize()

            repairAccountAuthMetadata(for: account, authBlob: resolvedAuth.blob)

            if let current = await waitForAccountReady(authBlob: resolvedAuth.blob, fallbackEmail: account.email) {
                await activateAccount(current)
                showStatus(Strings.L("已切换到 \(current.email)", en: "Switched to \(current.email)"))
            } else {
                NSLog("[CXSwitch] switchAccount: account/read not ready, falling back to selected account %@", account.email)
                await activateAccount(account)
                showStatus(Strings.L("已切换到 \(account.email)", en: "Switched to \(account.email)"))
                Task { [weak self] in
                    await self?.refreshCurrentAccount(force: true)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCurrentAccount() async {
        errorMessage = nil
        guard var current = currentAccount else {
            return
        }
        do {
            guard let authBlob = try accountStore.readAuthFile() else {
                errorMessage = Strings.missingAuthJSON
                return
            }
            current = enrichAccountMetadata(current, authBlob: authBlob)
            current.storedAuth = encodeStoredAuth(authBlob)
            current.authKeychainKey = nil
            current.lastUsedAt = Date()

            if !savedAccounts.contains(where: { $0.id == current.id }) {
                savedAccounts.append(current)
            } else {
                savedAccounts = savedAccounts.map { $0.id == current.id ? current : $0 }
            }
            savedAccounts = applyMasking(to: savedAccounts)
            try accountStore.saveRegistry(savedAccounts)
            rescheduleAutoRefreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAccount(_ account: Account) async {
        errorMessage = nil
        do {
            savedAccounts.removeAll { $0.id == account.id }
            try accountStore.saveRegistry(savedAccounts)
            cancelAutoRefreshTask(for: account.id)
            rescheduleAutoRefreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSavedAccounts(force: Bool) async {
        let accountIDs = savedAccounts.map(\.id)
        guard beginRefreshingAccounts(accountIDs) else { return }
        defer { endRefreshingAccounts(accountIDs) }

        var updated = savedAccounts
        for chunkStart in stride(from: 0, to: updated.count, by: 2) {
            let firstIndex = chunkStart
            let secondIndex = chunkStart + 1

            let firstAccount = updated[firstIndex]
            let secondAccount = secondIndex < updated.count ? updated[secondIndex] : nil

            async let firstResult = refreshAccountUsage(firstAccount, force: force)
            async let secondResult = secondAccount == nil ? nil : refreshAccountUsage(secondAccount!, force: force)

            let first = await firstResult
            updated[firstIndex] = applyUsageResult(to: firstAccount, result: first)

            if let secondAccount, let second = await secondResult {
                updated[secondIndex] = applyUsageResult(to: secondAccount, result: second)
            }
        }

        for account in updated {
            accountCacheByID[account.id] = account
        }
        savedAccounts = applyMasking(to: updated)
        syncCurrentAccountFromSavedAccounts()
        persistRegistrySnapshot()
        rescheduleAutoRefreshTasks()
    }

    func refreshCurrentAccount(force: Bool = true) async {
        guard let cachedCurrent = currentAccount else { return }
        guard beginRefreshingAccounts([cachedCurrent.id]) else { return }
        defer { endRefreshingAccounts([cachedCurrent.id]) }

        errorMessage = nil

        do {
            try await startAppServerIfNeeded()
            try await appServer.initialize()

            if let refreshed = try await fetchCurrentAccount() {
                mergeAccountCache(refreshed, updateCurrentAccount: true)
                return
            }
        } catch {
            NSLog("[CXSwitch] refreshCurrentAccount live refresh failed: %@", error.localizedDescription)
        }

        let usageResult = await refreshAccountUsage(cachedCurrent, force: force)
        let refreshed = applyUsageResult(to: cachedCurrent, result: usageResult)
        mergeAccountCache(refreshed, updateCurrentAccount: true)
    }

    func refreshAccount(_ account: Account, force: Bool = true) async {
        if account.id == currentAccount?.id {
            await refreshCurrentAccount(force: force)
            return
        }

        guard beginRefreshingAccounts([account.id]) else { return }
        defer { endRefreshingAccounts([account.id]) }

        let usageResult = await refreshAccountUsage(account, force: force)
        let refreshed = applyUsageResult(to: account, result: usageResult)
        mergeAccountCache(refreshed, updateCurrentAccount: false)
    }

    func startAddAccount() async {
        errorMessage = nil
        pendingRepairAccountID = nil
        await beginLoginFlow(repairTargetID: nil)
    }

    private func beginLoginFlow(repairTargetID: String?) async {
        errorMessage = nil
        do {
            try await startAppServerIfNeeded()
            try await appServer.initialize()
            let response: LoginStartResponse = try await appServer.sendRequest(
                method: "account/login/start",
                params: LoginStartParams()
            )

            pendingRepairAccountID = repairTargetID
            pendingLoginId = response.loginId
            loginFlow = LoginFlowState(
                active: true,
                loginId: response.loginId,
                authUrl: response.authUrl,
                status: repairTargetID == nil ? Strings.loginWaiting : Strings.L("等待重新授权完成", en: "Waiting for re-auth"),
                message: nil,
                error: nil,
                startedAt: Date(),
                completedAt: nil
            )

            if let urlString = response.authUrl, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            loginFlow = LoginFlowState.empty()
            errorMessage = error.localizedDescription
        }
    }

    func cancelAddAccount() async {
        errorMessage = nil
        guard loginFlow.active else { return }
        do {
            let params = LoginCancelParams(loginId: loginFlow.loginId)
            _ = try await appServer.sendRequest(method: "account/login/cancel", params: params) as EmptyResponse
            pendingLoginId = nil
            pendingRepairAccountID = nil
            loginFlow = LoginFlowState.empty()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importRefreshToken(_ rawToken: String) async {
        errorMessage = nil
        statusMessage = nil
        let token = sanitizeToken(rawToken)
        guard !token.isEmpty else {
            errorMessage = Strings.invalidRefreshToken
            return
        }

        refreshing = true
        defer { refreshing = false }
        NSLog("[CXSwitch] importRefreshToken: exchanging token...")
        do {
            var tokens = try await authService.exchangeRefreshToken(token)
            NSLog("[CXSwitch] importRefreshToken: exchange OK, extracting account info...")

            // Extract account_id from id_token JWT if not present
            if tokens.accountId == nil, let idToken = tokens.idToken {
                let claims = JWTDecoder.decodePayload(idToken)
                if let nested = claims?["https://api.openai.com/auth"] as? [String: Any] {
                    tokens.accountId = nested["chatgpt_account_id"] as? String
                }
            }

            NSLog("[CXSwitch] importRefreshToken: writing auth.json, accountId=%@", tokens.accountId ?? "nil")
            let authBlob = AuthBlob(
                authMode: "chatgpt",
                lastRefresh: ISO8601DateFormatter().string(from: Date()),
                tokens: tokens,
                openaiApiKey: nil
            )

            try accountStore.writeAuthFile(authBlob)
            try await appServer.restartAndInitialize()

            guard let account = await waitForAccountReady(authBlob: authBlob) else {
                errorMessage = Strings.accountInfoUnavailableAfterImport
                return
            }

            NSLog("[CXSwitch] importRefreshToken: got account %@", account.email)
            await activateAccount(account)
            showStatus(Strings.L("已导入 \(account.email)", en: "Imported \(account.email)"))
            NSLog("[CXSwitch] importRefreshToken: done, current=%@", currentAccount?.email ?? "nil")
        } catch {
            NSLog("[CXSwitch] importRefreshToken error: %@", error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func setMaskEmails(_ enabled: Bool) {
        preferences.maskEmails = enabled
        applyPreferencesSideEffects()
        savedAccounts = applyMasking(to: savedAccounts)
        if let current = currentAccount {
            currentAccount = applyMasking(to: current)
        }
        do {
            try accountStore.savePreferences(preferences)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openStatusPage() {
        guard let url = URL(string: "https://status.openai.com") else { return }
        NSWorkspace.shared.open(url)
    }

    func openSettings() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.novainfra.cx-switch", isDirectory: true)
        if let supportURL {
            NSWorkspace.shared.open(supportURL)
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func persistAccount(_ account: Account) async {
        let authBlob = await readAuthFileWithRetry()
        var entry = enrichAccountMetadata(account, authBlob: authBlob)
        entry = mergeAccountRecord(entry, preserving: accountCacheByID[entry.id] ?? savedAccounts.first(where: { $0.id == entry.id }))

        if let authBlob {
            entry.storedAuth = encodeStoredAuth(authBlob)
        }
        entry.authKeychainKey = nil

        accountCacheByID[entry.id] = entry
        if entry.isCurrent {
            savedAccounts = savedAccounts.map { account in
                var updated = account
                updated.isCurrent = (account.id == entry.id)
                return applyMasking(to: updated)
            }
        }

        do {
            if let index = savedAccounts.firstIndex(where: { $0.id == entry.id }) {
                savedAccounts[index] = applyMasking(to: entry)
            } else {
                savedAccounts.append(applyMasking(to: entry))
            }
            try accountStore.saveRegistry(savedAccounts)
            rescheduleAutoRefreshTasks()
        } catch {
            NSLog("[CXSwitch] persistAccount error: %@", error.localizedDescription)
        }
    }

    private func readAuthFileWithRetry(maxAttempts: Int = 5, delayNanoseconds: UInt64 = 300_000_000) async -> AuthBlob? {
        for attempt in 1...maxAttempts {
            if let authBlob = try? accountStore.readAuthFile() {
                return authBlob
            }
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        return nil
    }

    private func beginRefreshingAccounts(_ ids: [String]) -> Bool {
        let uniqueIDs = Array(Set(ids.filter { !$0.isEmpty }))
        guard !uniqueIDs.isEmpty else { return false }
        if uniqueIDs.contains(where: { refreshingAccountIDs.contains($0) }) {
            return false
        }

        for id in uniqueIDs {
            refreshingAccountIDs.insert(id)
        }
        refreshing = true
        return true
    }

    private func endRefreshingAccounts(_ ids: [String]) {
        for id in Set(ids) {
            refreshingAccountIDs.remove(id)
        }
        refreshing = !refreshingAccountIDs.isEmpty
    }

    private func rescheduleAutoRefreshTasks() {
        let uniqueAccounts = Dictionary(grouping: accountCacheByID.values, by: { $0.id }).compactMap { $0.value.first }
        let activeIDs = Set(uniqueAccounts.map(\.id))

        let staleIDs = autoRefreshTasks.keys.filter { !activeIDs.contains($0) }
        for id in staleIDs {
            cancelAutoRefreshTask(for: id)
        }

        for account in uniqueAccounts {
            scheduleAutoRefresh(for: account)
        }
    }

    private func scheduleAutoRefresh(for account: Account) {
        cancelAutoRefreshTask(for: account.id)

        guard let targetDate = nextAutoRefreshDate(for: account) else {
            autoRefreshTargets.removeValue(forKey: account.id)
            return
        }

        if let firedDate = autoRefreshFiredTargets[account.id], abs(firedDate.timeIntervalSince(targetDate)) < 1 {
            autoRefreshTargets[account.id] = targetDate
            return
        }

        autoRefreshTargets[account.id] = targetDate
        let delaySeconds = max(1.0, targetDate.timeIntervalSinceNow)
        let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)

        autoRefreshTasks[account.id] = Task { [weak self, accountID = account.id, targetDate] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.performAutoRefreshIfNeeded(accountID: accountID, targetDate: targetDate)
        }
    }

    private func cancelAutoRefreshTask(for accountID: String) {
        autoRefreshTasks[accountID]?.cancel()
        autoRefreshTasks.removeValue(forKey: accountID)
        autoRefreshTargets.removeValue(forKey: accountID)
        autoRefreshFiredTargets.removeValue(forKey: accountID)
    }

    private func performAutoRefreshIfNeeded(accountID: String, targetDate: Date) async {
        guard let scheduledTarget = autoRefreshTargets[accountID], abs(scheduledTarget.timeIntervalSince(targetDate)) < 1 else {
            return
        }
        guard autoRefreshFiredTargets[accountID] != targetDate else { return }

        autoRefreshFiredTargets[accountID] = targetDate

        guard let account = accountCacheByID[accountID]
            ?? savedAccounts.first(where: { $0.id == accountID })
            ?? currentAccount, account.id == accountID else {
            return
        }

        NSLog("[CXSwitch] auto refresh triggered for %@", account.email)
        if account.id == currentAccount?.id {
            await refreshCurrentAccount(force: true)
        } else {
            await refreshAccount(account, force: true)
        }
    }

    private func nextAutoRefreshDate(for account: Account) -> Date? {
        guard let snapshot = account.usageSnapshot else { return nil }

        let windows = snapshot.windows ?? [snapshot.primary, snapshot.secondary].compactMap { $0 }
        let candidates = windows.compactMap { window -> Date? in
            if let resetsAt = window.resetsAt {
                return resetsAt
            }
            guard let remainingSeconds = window.remainingSeconds, remainingSeconds >= 0 else {
                return nil
            }
            let anchor = snapshot.updatedAt ?? account.lastUsedAt ?? Date()
            return anchor.addingTimeInterval(TimeInterval(remainingSeconds))
        }

        return candidates.min()
    }

    private func encodeStoredAuth(_ blob: AuthBlob) -> String? {
        guard let data = try? JSONEncoder().encode(blob) else { return nil }
        return data.base64EncodedString()
    }

    private func decodeStoredAuth(_ stored: String) -> AuthBlob? {
        guard let data = Data(base64Encoded: stored) else { return nil }
        return try? JSONDecoder().decode(AuthBlob.self, from: data)
    }

    private func startAppServerIfNeeded() async throws {
        do {
            try appServer.start()
        } catch {
            try await retryStart()
        }
    }

    private func retryStart() async throws {
        var attempt = 0
        while attempt < 3 {
            attempt += 1
            do {
                try appServer.start()
                return
            } catch {
                let delay = UInt64(250 * attempt) * 1_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }
        throw CodexAppServerError.launchFailed
    }

    private func fetchCurrentAccount() async throws -> Account? {
        return try await fetchCurrentAccount(fromAuth: try accountStore.readAuthFile())
    }

    private func loadCurrentAccountForDashboard() async -> Account? {
        do {
            if let current = try await fetchCurrentAccount() {
                return current
            }
        } catch {
            NSLog("[CXSwitch] loadDashboard: current account fetch failed: %@", error.localizedDescription)
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return try? await fetchCurrentAccount()
    }

    private func fetchCurrentAccount(fromAuth authBlob: AuthBlob?, expectedAccountId: String? = nil, fallbackEmail: String? = nil) async throws -> Account? {
        for attempt in 0..<3 {
            if let account = try await fetchCurrentAccountOnce(fromAuth: authBlob, fallbackEmail: fallbackEmail) {
                if let expectedAccountId, account.id != expectedAccountId, attempt < 2 {
                    try await restartStabilizationDelay()
                    continue
                }
                return account
            }
            if attempt < 2 {
                try await restartStabilizationDelay()
            }
        }
        return nil
    }

    private func fetchCurrentAccountOnce(fromAuth authBlob: AuthBlob?, fallbackEmail: String? = nil) async throws -> Account? {
        let response: AccountReadResponse = try await appServer.sendRequest(method: "account/read", params: AccountReadParams())
        let email = response.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fallbackEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email, !email.isEmpty else { return nil }

        let accountType = resolvedAccountType(response.accountType, authBlob: authBlob)
        let planType = PlanTypeMapper.from(response.planType) ?? planType(from: authBlob)
        let accountId = response.chatgptAccountId ?? authBlob?.tokens?.accountId ?? email
        var account = Account(
            id: accountId,
            email: email,
            maskedEmail: email,
            accountType: accountType,
            planType: planType,
            chatgptAccountId: response.chatgptAccountId ?? authBlob?.tokens?.accountId,
            addedAt: Date(),
            lastUsedAt: Date(),
            usageSnapshot: nil,
            authKeychainKey: nil,
            usageError: nil,
            isCurrent: true
        )

        if let rateLimitsResponse: RateLimitsResponse = try? await appServer.sendRequest(method: "account/rateLimits/read", params: nil) {
            account.usageSnapshot = rateLimitsResponse.toUsageSnapshot()
        }

        account = applyMasking(to: account)
        return account
    }

    private func waitForAccountReady(authBlob: AuthBlob?, fallbackEmail: String? = nil) async -> Account? {
        for attempt in 1...5 {
            NSLog("[CXSwitch] waitForAccountReady: attempt %d", attempt)
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if let account = try? await fetchCurrentAccountOnce(fromAuth: authBlob, fallbackEmail: fallbackEmail) {
                return account
            }
        }
        return nil
    }

    private func refreshAccountUsage(_ account: Account, force: Bool) async -> (UsageSnapshot?, String?) {
        if !force, let updatedAt = account.usageSnapshot?.updatedAt {
            if Date().timeIntervalSince(updatedAt) < 60 {
                return (account.usageSnapshot, nil)
            }
        }

        do {
            let resolvedAuth = try resolveAuthBlob(for: account)
            guard let resolvedAuth else {
                return (nil, Strings.missingAuthForSelectedAccount)
            }

            let accessToken = resolvedAuth.blob.tokens?.accessToken
            let accountId = account.chatgptAccountId ?? resolvedAuth.blob.tokens?.accountId
            guard let accessToken, let accountId else {
                return (nil, Strings.missingToken)
            }

            let snapshot = try await usageProbe.probeUsage(accessToken: accessToken, chatgptAccountId: accountId)
            return (snapshot, nil)
        } catch {
            if error is UsageProbeError, let cachedSnapshot = account.usageSnapshot {
                NSLog("[CXSwitch] usage probe failed, using cached snapshot for %@: %@", account.email, String(describing: error))
                return (cachedSnapshot, nil)
            }

            return (nil, userFacingUsageError(for: error))
        }
    }

    private func applyUsageResult(to account: Account, result: (UsageSnapshot?, String?)) -> Account {
        var updated = account
        updated.usageSnapshot = result.0
        updated.usageError = result.1
        return updated
    }

    private func applyMasking(to account: Account) -> Account {
        var updated = account
        if preferences.maskEmails == true {
            updated.maskedEmail = EmailMasker.mask(account.email)
        } else {
            updated.maskedEmail = account.email
        }
        return updated
    }

    private func applyMasking(to accounts: [Account]) -> [Account] {
        accounts.map { applyMasking(to: $0) }
    }

    private func visibleEmail(for account: Account) -> String {
        if preferences.maskEmails == true {
            return account.maskedEmail
        }
        return account.email
    }

    private func mergeAccountCache(_ account: Account, updateCurrentAccount: Bool) {
        let existing = accountCacheByID[account.id]
            ?? savedAccounts.first(where: { $0.id == account.id })
            ?? (currentAccount?.id == account.id ? currentAccount : nil)
        let merged = mergeAccountRecord(account, preserving: existing)

        accountCacheByID[merged.id] = merged
        let maskedAccount = applyMasking(to: merged)
        if let index = savedAccounts.firstIndex(where: { $0.id == merged.id }) {
            savedAccounts[index] = maskedAccount
        } else {
            savedAccounts.append(maskedAccount)
        }

        if updateCurrentAccount || currentAccount?.id == merged.id {
            currentAccount = maskedAccount
        }

        if updateCurrentAccount || merged.isCurrent {
            markCurrentAccount(maskedAccount)
        }
        persistRegistrySnapshot()
        rescheduleAutoRefreshTasks()
    }

    private func syncCurrentAccountFromSavedAccounts() {
        guard let currentID = currentAccount?.id ?? savedAccounts.first(where: \.isCurrent)?.id else {
            return
        }
        if let refreshed = accountCacheByID[currentID] {
            currentAccount = applyMasking(to: refreshed)
        } else if let refreshed = savedAccounts.first(where: { $0.id == currentID }) {
            currentAccount = applyMasking(to: refreshed)
        }
    }

    private func normalizeAccountsFromStoredAuth(_ accounts: [Account]) -> (accounts: [Account], changed: Bool) {
        var changed = false
        let normalized = accounts.map { account in
            let enriched = enrichAccountMetadata(account)
            if enriched.accountType != account.accountType
                || enriched.planType != account.planType
                || enriched.chatgptAccountId != account.chatgptAccountId
                || enriched.authKeychainKey != account.authKeychainKey
                || enriched.storedAuth != account.storedAuth {
                changed = true
            }
            return enriched
        }
        return (normalized, changed)
    }

    private func repairAccountsWithCurrentAuthIfPossible(_ accounts: [Account], currentAuthBlob: AuthBlob?) -> (accounts: [Account], changed: Bool) {
        guard let currentAuthBlob else { return (accounts, false) }
        let identity = authIdentity(from: currentAuthBlob)
        guard identity.hasMeaningfulIdentity else { return (accounts, false) }

        var changed = false
        let repaired = accounts.map { account in
            guard canRepair(account: account, with: identity) else {
                return account
            }

            var updated = enrichAccountMetadata(account, authBlob: currentAuthBlob)
            if updated.storedAuth == nil || decodeStoredAuth(updated.storedAuth ?? "")?.tokens?.refreshToken?.isEmpty != false {
                updated.storedAuth = encodeStoredAuth(currentAuthBlob)
            }
            updated.authKeychainKey = nil
            if shouldBackfillAccountType(updated.accountType) {
                updated.accountType = AccountTypeMapper.from(authBlob: currentAuthBlob)
            }
            if updated.planType == nil {
                updated.planType = planType(from: currentAuthBlob)
            }
            if updated.chatgptAccountId == nil {
                updated.chatgptAccountId = chatgptAccountID(from: currentAuthBlob)
            }

            if updated.storedAuth != account.storedAuth
                || updated.accountType != account.accountType
                || updated.planType != account.planType
                || updated.chatgptAccountId != account.chatgptAccountId
                || updated.authKeychainKey != account.authKeychainKey {
                changed = true
            }
            return updated
        }

        return (repaired, changed)
    }

    private func canRepair(account: Account, with identity: AuthIdentity) -> Bool {
        if let currentAccountID = identity.chatgptAccountID {
            if account.id == currentAccountID || account.chatgptAccountId == currentAccountID {
                return true
            }
        }

        if let email = identity.email?.lowercased(), !email.isEmpty {
            let accountEmail = account.email.lowercased()
            if accountEmail == email {
                return true
            }
        }

        return false
    }

    private func enrichAccountMetadata(_ account: Account, authBlob: AuthBlob? = nil) -> Account {
        var updated = account
        let resolvedAuthBlob = authBlob ?? account.storedAuth.flatMap(decodeStoredAuth)

        if shouldBackfillAccountType(updated.accountType) {
            updated.accountType = AccountTypeMapper.from(authBlob: resolvedAuthBlob)
        }

        if updated.planType == nil {
            updated.planType = planType(from: resolvedAuthBlob)
        }

        if updated.chatgptAccountId == nil {
            updated.chatgptAccountId = chatgptAccountID(from: resolvedAuthBlob)
        }

        if updated.storedAuth == nil, let resolvedAuthBlob {
            updated.storedAuth = encodeStoredAuth(resolvedAuthBlob)
        }

        return updated
    }

    private func shouldBackfillAccountType(_ value: AccountType?) -> Bool {
        value == nil || value == .unknown
    }

    private func resolvedAccountType(_ responseValue: String?, authBlob: AuthBlob?) -> AccountType? {
        let responseType = AccountTypeMapper.from(responseValue)
        if let responseType, responseType != .unknown {
            return responseType
        }
        return AccountTypeMapper.from(authBlob: authBlob)
    }

    private func planType(from authBlob: AuthBlob?) -> PlanType? {
        guard
            let authBlob,
            let idToken = authBlob.tokens?.idToken,
            let claims = JWTDecoder.decodePayload(idToken),
            let nested = claims["https://api.openai.com/auth"] as? [String: Any],
            let planType = nested["chatgpt_plan_type"] as? String
        else {
            return nil
        }
        return PlanTypeMapper.from(planType)
    }

    private func chatgptAccountID(from authBlob: AuthBlob?) -> String? {
        guard
            let authBlob,
            let idToken = authBlob.tokens?.idToken,
            let claims = JWTDecoder.decodePayload(idToken),
            let nested = claims["https://api.openai.com/auth"] as? [String: Any]
        else {
            return authBlob?.tokens?.accountId
        }

        if let accountID = nested["chatgpt_account_id"] as? String, !accountID.isEmpty {
            return accountID
        }
        return authBlob.tokens?.accountId
    }

    private struct AuthIdentity {
        let email: String?
        let chatgptAccountID: String?
        let planType: String?
        let refreshToken: String?

        var hasMeaningfulIdentity: Bool {
            let hasEmail = !(email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasAccountID = !(chatgptAccountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasEmail || hasAccountID
        }
    }

    private func authIdentity(from authBlob: AuthBlob) -> AuthIdentity {
        let idToken = authBlob.tokens?.idToken
        let claims = JWTDecoder.decodePayload(idToken)
        let nested = claims?["https://api.openai.com/auth"] as? [String: Any]
        return AuthIdentity(
            email: claims?["email"] as? String,
            chatgptAccountID: nested?["chatgpt_account_id"] as? String ?? authBlob.tokens?.accountId,
            planType: nested?["chatgpt_plan_type"] as? String,
            refreshToken: authBlob.tokens?.refreshToken
        )
    }

    private func persistRegistrySnapshot() {
        do {
            try accountStore.saveRegistry(savedAccounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct ResolvedAuthBlob {
        let blob: AuthBlob
        let sourceAccountID: String?
    }

    private func resolveAuthBlob(for account: Account) throws -> ResolvedAuthBlob? {
        let allKnownAccounts = knownAccounts(for: account)

        for candidate in allKnownAccounts {
            if let storedAuth = candidate.storedAuth,
               let blob = decodeStoredAuth(storedAuth) {
                return ResolvedAuthBlob(blob: blob, sourceAccountID: candidate.id)
            }
        }

        return nil
    }

    private func repairAccountAuthMetadata(for account: Account, authBlob: AuthBlob) {
        var repaired = enrichAccountMetadata(account, authBlob: authBlob)

        repaired.authKeychainKey = nil
        repaired.storedAuth = encodeStoredAuth(authBlob)

        repaired.lastUsedAt = Date()
        accountCacheByID[repaired.id] = repaired

        if let index = savedAccounts.firstIndex(where: { $0.id == repaired.id }) {
            savedAccounts[index] = applyMasking(to: repaired)
        } else {
            savedAccounts.append(applyMasking(to: repaired))
        }

        if currentAccount?.id == repaired.id {
            currentAccount = applyMasking(to: repaired)
        }

        persistRegistrySnapshot()
    }

    private func finishRepairLogin(for targetAccountID: String) async {
        guard let target = accountCacheByID[targetAccountID] ?? savedAccounts.first(where: { $0.id == targetAccountID }) else {
            await forceReloadDashboard()
            return
        }

        guard let authBlob = await readAuthFileWithRetry() else {
            errorMessage = Strings.missingAuthJSON
            await forceReloadDashboard()
            return
        }

        let identity = authIdentity(from: authBlob)
        guard canRepair(account: target, with: identity) else {
            let actualLabel = identity.email ?? identity.chatgptAccountID ?? Strings.currentAccount
            errorMessage = Strings.L(
                "重新授权得到的是 \(actualLabel)，与待修复账号 \(target.email) 不匹配",
                en: "Re-auth returned \(actualLabel), which does not match \(target.email)"
            )
            await forceReloadDashboard()
            return
        }

        var liveAccount = try? await fetchCurrentAccount(fromAuth: authBlob, fallbackEmail: target.email)
        if liveAccount == nil {
            liveAccount = await waitForAccountReady(authBlob: authBlob, fallbackEmail: target.email)
        }
        let repaired = makeRepairedAccountRecord(target: target, liveAccount: liveAccount, authBlob: authBlob)
        replaceAccountRecord(target: target, with: repaired)
        showStatus(Strings.L("已修复 \(repaired.email)", en: "Repaired \(repaired.email)"))
        await forceReloadDashboard()
    }

    private func makeRepairedAccountRecord(target: Account, liveAccount: Account?, authBlob: AuthBlob) -> Account {
        var repaired = liveAccount ?? target
        repaired.addedAt = target.addedAt
        repaired.lastUsedAt = Date()
        repaired.isCurrent = true
        repaired.storedAuth = encodeStoredAuth(authBlob)
        repaired.authKeychainKey = nil
        repaired = enrichAccountMetadata(repaired, authBlob: authBlob)
        return repaired
    }

    private func replaceAccountRecord(target: Account, with replacement: Account) {
        let targetIndex = savedAccounts.firstIndex(where: { $0.id == target.id })

        accountCacheByID.removeValue(forKey: target.id)
        accountCacheByID[replacement.id] = replacement

        savedAccounts.removeAll { $0.id == target.id || $0.id == replacement.id }
        let maskedReplacement = applyMasking(to: replacement)
        if let targetIndex, targetIndex <= savedAccounts.count {
            savedAccounts.insert(maskedReplacement, at: targetIndex)
        } else {
            savedAccounts.append(maskedReplacement)
        }

        currentAccount = maskedReplacement
        markCurrentAccount(maskedReplacement)
        persistRegistrySnapshot()
        rescheduleAutoRefreshTasks()
    }

    private func migrateLegacyKeychainAccountsIfNeeded(_ accounts: [Account]) throws -> [Account] {
        guard !legacyKeychainMigrationCompleted else { return accounts }

        var migrated = accounts
        var changed = false

        for index in migrated.indices {
            var account = migrated[index]

            if let storedAuth = account.storedAuth, !storedAuth.isEmpty {
                if account.authKeychainKey != nil {
                    account.authKeychainKey = nil
                    migrated[index] = account
                    changed = true
                }
                continue
            }

            guard let keychainKey = account.authKeychainKey, !keychainKey.isEmpty else {
                continue
            }

            if let blob = try legacyKeychainService.loadAuthBlob(accountId: keychainKey)
                ?? legacyKeychainService.loadAuthBlob(accountId: account.id) {
                account.storedAuth = encodeStoredAuth(blob)
            }

            account.authKeychainKey = nil
            migrated[index] = account
            changed = true

            try? legacyKeychainService.deleteAuthBlob(accountId: keychainKey)
            if keychainKey != account.id {
                try? legacyKeychainService.deleteAuthBlob(accountId: account.id)
            }
        }

        if changed {
            try accountStore.saveRegistry(migrated)
        }

        legacyKeychainMigrationCompleted = true
        return migrated
    }

    private func userFacingUsageError(for error: Error) -> String? {
        if error is UsageProbeError {
            NSLog("[CXSwitch] usage probe failed: %@", String(describing: error))
            return nil
        }
        return error.localizedDescription
    }

    private func knownAccounts(for account: Account) -> [Account] {
        var candidates: [Account] = [account]

        if let cached = accountCacheByID[account.id] {
            candidates.append(cached)
        }

        if let persisted = try? accountStore.loadRegistry() {
            if let direct = persisted.first(where: { $0.id == account.id }) {
                candidates.append(direct)
            }

            let email = account.email.lowercased()
            if !email.isEmpty {
                candidates.append(contentsOf: persisted.filter {
                    $0.email.lowercased() == email && $0.id != account.id
                })
            }
        }

        let currentEmail = account.email.lowercased()
        if !currentEmail.isEmpty {
            candidates.append(contentsOf: savedAccounts.filter {
                $0.email.lowercased() == currentEmail && $0.id != account.id
            })
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    private func markCurrentAccount(_ current: Account) {
        savedAccounts = savedAccounts.map { account in
            var updated = account
            updated.isCurrent = (account.id == current.id)
            return updated
        }
    }

    private func activateAccount(_ account: Account) async {
        await persistAccount(account)
        currentAccount = applyMasking(to: account)
        markCurrentAccount(account)
        dashboardLoaded = true
    }

    private func mergeAccountRecord(_ incoming: Account, preserving existing: Account?) -> Account {
        guard let existing else { return incoming }

        var merged = incoming

        if merged.storedAuth == nil || merged.storedAuth?.isEmpty == true {
            merged.storedAuth = existing.storedAuth
        }

        if merged.authKeychainKey == nil || merged.authKeychainKey?.isEmpty == true {
            merged.authKeychainKey = existing.authKeychainKey
        }

        if merged.planType == nil {
            merged.planType = existing.planType
        }

        if shouldBackfillAccountType(merged.accountType),
           let existingType = existing.accountType,
           existingType != .unknown {
            merged.accountType = existingType
        }

        if merged.chatgptAccountId == nil {
            merged.chatgptAccountId = existing.chatgptAccountId
        }

        if merged.usageSnapshot == nil {
            merged.usageSnapshot = existing.usageSnapshot
        }

        if merged.usageError == nil {
            merged.usageError = existing.usageError
        }

        if existing.addedAt < merged.addedAt {
            merged.addedAt = existing.addedAt
        }

        if let existingLastUsedAt = existing.lastUsedAt {
            if let incomingLastUsedAt = merged.lastUsedAt {
                merged.lastUsedAt = max(existingLastUsedAt, incomingLastUsedAt)
            } else {
                merged.lastUsedAt = existingLastUsedAt
            }
        }

        merged.isCurrent = merged.isCurrent || existing.isCurrent
        return merged
    }

    private func applyPreferencesSideEffects() {
        Strings.languageProvider = { [weak self] in
            self?.preferences.language ?? Preferences.defaultLanguage
        }
    }

    private func sanitizeToken(_ token: String) -> String {
        var cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned.removeFirst()
            cleaned.removeLast()
        }
        return cleaned
    }

    private func restartStabilizationDelay() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    }

    private func handle(notification: ServerNotification) {
        guard notification.method == "account/login/completed" else {
            return
        }

        guard loginFlow.active else {
            return
        }

        if let paramsData = notification.paramsData,
           let completed = try? JSONDecoder().decode(LoginCompletedNotification.self, from: paramsData) {
            let expectedLoginId = pendingLoginId ?? loginFlow.loginId
            if let completedLoginId = completed.loginId, completedLoginId != expectedLoginId {
                return
            }
        }

        pendingLoginId = nil
        let repairTargetID = pendingRepairAccountID
        pendingRepairAccountID = nil
        loginFlow.status = Strings.loginCompleted
        loginFlow.message = nil
        loginFlow.error = nil
        loginFlow.completedAt = Date()

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let repairTargetID {
                await self.finishRepairLogin(for: repairTargetID)
            } else {
                await self.forceReloadDashboard()
            }
            self.loginFlow = .empty()
        }
    }
}

private struct AccountReadResponse: Decodable {
    let account: AccountInfo?
    let requiresOpenaiAuth: Bool?

    struct AccountInfo: Decodable {
        let type: String?
        let email: String?
        let planType: String?
    }

    var email: String? { account?.email }
    var planType: String? { account?.planType }
    var accountType: String? { account?.type }
    var chatgptAccountId: String? { nil }
}

private struct LoginStartResponse: Decodable {
    let loginId: String?
    let authUrl: String?
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot?]?

    struct RateLimitSnapshot: Decodable {
        let limitId: String?
        let planType: String?
        let primary: WindowData?
        let secondary: WindowData?
    }

    struct WindowData: Decodable {
        let usedPercent: Double?
        let resetsAt: Double?
        let windowDurationMins: Int?
    }

    func toUsageSnapshot() -> UsageSnapshot? {
        let snapshot = rateLimitsByLimitId?["codex"] ?? rateLimits
        guard let snapshot else { return nil }

        let primary = snapshot.primary.map { w in
            UsageWindow(
                label: "5 Hours",
                windowDurationMins: w.windowDurationMins ?? 300,
                usedPercent: w.usedPercent ?? 0,
                resetsAt: w.resetsAt.map { Date(timeIntervalSince1970: $0) },
                remainingSeconds: w.resetsAt.map { max(0, Int($0 - Date().timeIntervalSince1970)) },
                resetText: nil
            )
        }
        let secondary = snapshot.secondary.map { w in
            UsageWindow(
                label: "Weekly",
                windowDurationMins: w.windowDurationMins ?? 10080,
                usedPercent: w.usedPercent ?? 0,
                resetsAt: w.resetsAt.map { Date(timeIntervalSince1970: $0) },
                remainingSeconds: w.resetsAt.map { max(0, Int($0 - Date().timeIntervalSince1970)) },
                resetText: nil
            )
        }

        guard primary != nil || secondary != nil else { return nil }

        return UsageSnapshot(
            limitId: snapshot.limitId,
            planType: PlanTypeMapper.from(snapshot.planType),
            updatedAt: Date(),
            primary: primary,
            secondary: secondary,
            credits: nil
        )
    }
}

private struct AccountReadParams: Encodable {
    let refreshToken: Bool = true
}

private struct LoginStartParams: Encodable {
    let type: String = "chatgpt"
}

private struct LoginCancelParams: Encodable {
    let loginId: String?
}

private struct EmptyResponse: Decodable {}

private struct LoginCompletedNotification: Decodable {
    let loginId: String?
}

private enum PlanTypeMapper {
    static func from(_ value: String?) -> PlanType? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "chatgpt_", with: "")
            .replacingOccurrences(of: "codex_", with: "")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "free", "personal", "individual":
            return .free
        case "go":
            return .go
        case "plus":
            return .plus
        case "pro":
            return .pro
        case "team", "teams":
            return .team
        case "business", "enterprise_business":
            return .business
        case "enterprise":
            return .enterprise
        case "edu", "education":
            return .edu
        default:
            return PlanType(rawValue: normalized) ?? .unknown
        }
    }
}

private enum AccountTypeMapper {
    static func from(_ value: String?) -> AccountType? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")

        switch normalized {
        case "oauth":
            return .oauth
        case "setup-token", "setuptoken":
            return .setupToken
        case "apikey", "api-key", "api_key":
            return .apiKey
        case "upstream":
            return .upstream
        case "bedrock":
            return .bedrock
        case "unknown":
            return .unknown
        default:
            return AccountType(rawValue: normalized) ?? .unknown
        }
    }

    static func from(authBlob: AuthBlob?) -> AccountType? {
        guard let authBlob else { return nil }

        if let apiKey = authBlob.openaiApiKey, !apiKey.isEmpty {
            return .apiKey
        }

        if let authMode = authBlob.authMode?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !authMode.isEmpty {
            switch authMode {
            case "chatgpt", "oauth":
                return .oauth
            case "setup-token", "setup_token":
                return .setupToken
            case "apikey", "api-key", "api_key":
                return .apiKey
            default:
                return from(authMode)
            }
        }

        return nil
    }
}
