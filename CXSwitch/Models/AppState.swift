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
    var switchingAccountID: String?

    nonisolated(unsafe) private let accountStore: AccountStore
    nonisolated(unsafe) private let accountDB: AccountDatabase
    nonisolated(unsafe) private let legacyKeychainService: any KeychainStoring
    private let appServer: any CodexAppServering
    nonisolated(unsafe) private let usageProbe: UsageProbe
    private let authService: any AuthTokenExchanging
    private var pendingLoginId: String?
    private var pendingRepairAccountID: String?
    private var dashboardLoading = false
    private var dashboardLoaded = false
    private var refreshingAccountIDs: Set<String> = []
    private var autoRefreshTasks: [String: Task<Void, Never>] = [:]
    private var autoRefreshTargets: [String: Date] = [:]
    private var autoRefreshFiredTargets: [String: Date] = [:]
    private var activeTransitionGeneration: UInt64 = 0
    private var activeTransitionTask: Task<Void, Never>?
    private var fileWatchSources: [DispatchSourceFileSystemObject] = []

    private struct TransitionSnapshot {
        let currentAccount: Account?
        let savedAccounts: [Account]
        let authBlob: AuthBlob?
    }

    init(
        accountStore: AccountStore? = nil,
        accountDB: AccountDatabase? = nil,
        legacyKeychainService: any KeychainStoring = KeychainService(),
        appServer: any CodexAppServering = CodexAppServer(),
        usageProbe: UsageProbe = UsageProbe(),
        authService: any AuthTokenExchanging = AuthService()
    ) {
        let store: AccountStore
        do {
            store = try accountStore ?? AccountStore()
        } catch {
            NSLog("[CXSwitch] FATAL: cannot initialize AccountStore: \(error)")
            store = try! AccountStore(appSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent("cx-switch-fallback"))
        }
        self.accountStore = store

        let db: AccountDatabase
        do {
            db = try accountDB ?? AccountDatabase(appSupportURL: store.appSupportDirectoryURL)
        } catch {
            NSLog("[CXSwitch] FATAL: cannot initialize AccountDatabase: \(error)")
            db = try! AccountDatabase(appSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent("cx-switch-fallback"))
        }
        self.accountDB = db
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
        self.switchingAccountID = nil

        Strings.languageProvider = { [weak self] in
            self?.preferences.language ?? Preferences.defaultLanguage
        }

        try? self.accountDB.migrateIfNeeded(
            registryPath: store.registryFileURL.path,
            keychainService: legacyKeychainService
        )

        appServer.setNotificationHandler { [weak self] notification in
            Task { @MainActor in
                self?.handle(notification: notification)
            }
        }

        // Pre-load cached accounts so UI is never empty on first appear
        if let cachedAccounts = try? db.loadAllAccounts(), !cachedAccounts.isEmpty {
            savedAccounts = cachedAccounts
            if let current = cachedAccounts.first(where: { $0.isCurrent }) {
                currentAccount = current
            }
        }

        startFileWatching()
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

    private func clearTransientStatus() {
        statusMessage = nil
        errorMessage = nil
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }

        return nsError.localizedDescription.localizedCaseInsensitiveContains("cancelled")
    }

    func loadDashboard(force: Bool) async {
        guard !dashboardLoading else { return }
        if !force, dashboardLoaded { return }

        dashboardLoading = true
        defer {
            dashboardLoading = false
        }
        errorMessage = nil
        do {
            // Step 1: Load cache immediately — user sees data right away
            let prefs = try accountStore.loadPreferences()
            preferences = prefs
            applyPreferencesSideEffects()
            applyTheme()

            var currentAuthBlob = try? accountStore.readAuthFile()

            let cachedAccounts = try loadCachedAccounts()
            let deduplicatedRegistry = deduplicateAccounts(cachedAccounts)
            if deduplicatedRegistry.changed {
                try accountDB.saveAccountsSnapshot(deduplicatedRegistry.accounts)
            }

            savedAccounts = applyMasking(to: deduplicatedRegistry.accounts)
            NSLog("[CXSwitch] loadDashboard: cache loaded, %d accounts", deduplicatedRegistry.accounts.count)

            // Show cached current account instantly
            if let cached = deduplicatedRegistry.accounts.first(where: { $0.isCurrent }) {
                currentAccount = applyMasking(to: cached)
                NSLog("[CXSwitch] loadDashboard: cached current = %@", cached.email)
            }
            rescheduleAutoRefreshTasks()

            // Step 2: Background — start app-server and fetch live data
            NSLog("[CXSwitch] loadDashboard: starting app server...")
            if currentAuthBlob == nil {
                let dbCurrent = try? accountDB.currentAccount()
                if let restoredCurrent = dbCurrent ?? nil {
                    let dbCredential = try? accountDB.loadCredential(accountId: restoredCurrent.id)
                    if let restoredCredential = dbCredential ?? nil {
                        try accountStore.writeAuthFile(restoredCredential)
                        currentAuthBlob = restoredCredential
                    }
                }
            }
            try await startAppServerIfNeeded()
            try await appServer.initialize()

            let current = await loadCurrentAccountForDashboard(authBlob: currentAuthBlob)
            if let current {
                currentAccount = current
                NSLog("[CXSwitch] loadDashboard: live current = %@", current.email)
                persistAccount(current, authBlob: currentAuthBlob)
            } else if currentAccount == nil {
                NSLog("[CXSwitch] loadDashboard: no current account")
            }

            dashboardLoaded = true

        } catch {
            if isCancellationError(error) {
                clearTransientStatus()
                return
            }
            NSLog("[CXSwitch] loadDashboard error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(to account: Account) async {
        guard switchingAccountID == nil else { return }
        guard account.id != currentAccount?.id else { return }

        errorMessage = nil
        statusMessage = nil
        switchingAccountID = account.id

        do {
            guard let authBlob = loadCredential(for: account) else {
                await beginLoginFlow(repairTargetID: account.id)
                return
            }

            let previousState = transitionSnapshot()
            guard beginRefreshingAccounts([account.id]) else {
                switchingAccountID = nil
                return
            }

            NSLog("[CXSwitch] switchAccount: writing auth.json for %@", account.email)
            try accountStore.writeAuthFile(authBlob)
            NSLog("[CXSwitch] switchAccount: restarting app server")
            try await appServer.restartAndInitialize()
            NSLog("[CXSwitch] switchAccount: app server restarted")

            let optimistic = preparedOptimisticAccount(from: account, authBlob: authBlob)
            try? accountDB.setCurrentAccount(id: account.id)
            optimisticallyActivateAccount(optimistic)
            showStatus(Strings.L("正在切换到 \(optimistic.email)…", en: "Switching to \(optimistic.email)..."))

            let generation = beginTransition()
            activeTransitionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.reconcileActiveAccountTransition(
                    optimisticAccount: optimistic,
                    authBlob: authBlob,
                    previousState: previousState,
                    generation: generation,
                    successMessage: Strings.L("已切换到 \(optimistic.email)", en: "Switched to \(optimistic.email)"),
                    failureMessage: Strings.L("切换失败，已恢复上一个账号", en: "Switch failed, restored previous account")
                )
            }
        } catch {
            if isCancellationError(error) {
                clearTransientStatus()
                switchingAccountID = nil
                endRefreshingAccounts([account.id])
                return
            }
            NSLog("[CXSwitch] switchAccount failed: %@", error.localizedDescription)
            endRefreshingAccounts([account.id])
            switchingAccountID = nil
            errorMessage = error.localizedDescription
        }
    }

    func saveCurrentAccount() async {
        errorMessage = nil
        guard var current = currentAccount else {
            return
        }
        let authBlob = loadCredential(for: current)
        current = enrichAccountMetadata(current, authBlob: authBlob)
        current.lastUsedAt = Date()

        if !savedAccounts.contains(where: { $0.id == current.id }) {
            savedAccounts.append(current)
        } else {
            savedAccounts = savedAccounts.map { $0.id == current.id ? current : $0 }
        }
        savedAccounts = applyMasking(to: savedAccounts)
        try? accountDB.saveAccount(current)
        if let authBlob {
            try? accountDB.saveCredential(accountId: current.id, authBlob: authBlob)
        }
        try? accountDB.setCurrentAccount(id: current.id)
        rescheduleAutoRefreshTasks()
    }

    func removeAccount(_ account: Account) async {
        errorMessage = nil
        savedAccounts.removeAll { $0.id == account.id }
        try? accountDB.deleteAccount(id: account.id)
        cancelAutoRefreshTask(for: account.id)
        rescheduleAutoRefreshTasks()
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

        savedAccounts = applyMasking(to: updated)
        persistRefreshedAccounts(updated, currentAccountID: currentAccount?.id ?? updated.first(where: \.isCurrent)?.id)
        rescheduleAutoRefreshTasks()
    }

    func refreshCurrentAccount(force: Bool = true) async {
        guard let cachedCurrent = currentAccount else { return }
        guard beginRefreshingAccounts([cachedCurrent.id]) else { return }
        defer { endRefreshingAccounts([cachedCurrent.id]) }

        errorMessage = nil
        let authBlob = loadCredential(for: cachedCurrent)

        do {
            try await startAppServerIfNeeded()
            try await appServer.initialize()

            if let refreshed = try await fetchCurrentAccount(fromAuth: authBlob) {
                persistAccountSnapshot(refreshed, updateCurrentAccount: true)
                return
            }
        } catch {
            NSLog("[CXSwitch] refreshCurrentAccount live refresh failed: %@", error.localizedDescription)
        }

        let usageResult = await refreshAccountUsage(cachedCurrent, force: force)
        let refreshed = applyUsageResult(to: cachedCurrent, result: usageResult)
        persistAccountSnapshot(refreshed, updateCurrentAccount: true)
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
        persistAccountSnapshot(refreshed, updateCurrentAccount: false)
    }

    func refreshAllAccounts(force: Bool = true) async {
        var accountsToRefresh: [Account] = []
        let currentAccountID = currentAccount?.id

        if let current = currentAccount ?? savedAccounts.first(where: { $0.isCurrent }) {
            accountsToRefresh.append(current)
        }

        accountsToRefresh.append(contentsOf: savedAccounts.filter { account in
            !accountsToRefresh.contains(where: { $0.id == account.id })
        })

        await withTaskGroup(of: Void.self) { group in
            for account in accountsToRefresh {
                group.addTask { [weak self] in
                    guard let self else { return }
                    if account.id == currentAccountID {
                        await self.refreshCurrentAccount(force: force)
                    } else {
                        await self.refreshAccount(account, force: force)
                    }
                }
            }

            for await _ in group {
            }
        }
    }

    func startAddAccount() async {
        errorMessage = nil
        pendingRepairAccountID = nil
        switchingAccountID = nil
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
            switchingAccountID = repairTargetID
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
            if isCancellationError(error) {
                clearTransientStatus()
                switchingAccountID = nil
                loginFlow = LoginFlowState.empty()
                pendingLoginId = nil
                pendingRepairAccountID = nil
                return
            }
            loginFlow = LoginFlowState.empty()
            switchingAccountID = nil
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
            switchingAccountID = nil
            loginFlow = LoginFlowState.empty()
        } catch {
            if isCancellationError(error) {
                clearTransientStatus()
                pendingLoginId = nil
                pendingRepairAccountID = nil
                switchingAccountID = nil
                loginFlow = LoginFlowState.empty()
                return
            }
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

        NSLog("[CXSwitch] importRefreshToken: exchanging token...")
        do {
            let previousState = transitionSnapshot()
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
            let optimistic = provisionalImportedAccount(from: authBlob)
            if let optimistic {
                guard beginRefreshingAccounts([optimistic.id]) else {
                    switchingAccountID = nil
                    return
                }
                switchingAccountID = optimistic.id
                try? accountDB.saveAccount(optimistic)
                try? accountDB.saveCredential(accountId: optimistic.id, authBlob: authBlob)
                try? accountDB.setCurrentAccount(id: optimistic.id)
                optimisticallyActivateAccount(optimistic)
                showStatus(Strings.L("已导入 \(optimistic.email)，正在同步…", en: "Imported \(optimistic.email), syncing..."))

                let generation = beginTransition()
                activeTransitionTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.reconcileActiveAccountTransition(
                        optimisticAccount: optimistic,
                        authBlob: authBlob,
                        previousState: previousState,
                        generation: generation,
                        successMessage: Strings.L("已导入 \(optimistic.email)", en: "Imported \(optimistic.email)"),
                        failureMessage: Strings.L("导入失败，已恢复上一个账号", en: "Import failed, restored previous account")
                    )
                }
            } else {
                guard let account = await waitForAccountReady(authBlob: authBlob) else {
                    rollbackTransition(
                        accountID: nil,
                        to: previousState,
                        error: Strings.accountInfoUnavailableAfterImport
                    )
                    return
                }

                NSLog("[CXSwitch] importRefreshToken: got account %@", account.email)
                activateAccount(account, authBlob: authBlob)
                try? accountDB.saveAccount(account)
                try? accountDB.saveCredential(accountId: account.id, authBlob: authBlob)
                try? accountDB.setCurrentAccount(id: account.id)
                showStatus(Strings.L("已导入 \(account.email)", en: "Imported \(account.email)"))
                NSLog("[CXSwitch] importRefreshToken: done, current=%@", currentAccount?.email ?? "nil")
            }
        } catch {
            if isCancellationError(error) {
                clearTransientStatus()
                switchingAccountID = nil
                return
            }
            NSLog("[CXSwitch] importRefreshToken error: %@", error.localizedDescription)
            switchingAccountID = nil
            errorMessage = error.localizedDescription
        }
    }

    func setMaskEmails(_ enabled: Bool) {
        guard (preferences.maskEmails ?? false) != enabled else { return }
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

    func setLanguage(_ language: String) {
        guard preferences.language != language else { return }
        preferences.language = language
        applyPreferencesSideEffects()
        do {
            try accountStore.savePreferences(preferences)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setTheme(_ theme: String) {
        let normalizedTheme = normalizedThemeValue(theme)
        guard normalizedTheme != normalizedThemeValue(preferences.theme) else { return }
        preferences.theme = normalizedTheme
        applyTheme()
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
        cancelAllAutoRefreshTasks()
        appServer.shutdown()
        NSApplication.shared.terminate(nil)
    }

    static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.1"
    }()

    private func persistAccount(_ account: Account, authBlob: AuthBlob?) {
        var entry = enrichAccountMetadata(account, authBlob: authBlob)
        entry = mergeAccountRecord(entry, preserving: savedAccounts.first(where: { $0.id == entry.id }) ?? (currentAccount?.id == entry.id ? currentAccount : nil))
        if entry.isCurrent {
            savedAccounts = savedAccounts.map { account in
                var updated = account
                updated.isCurrent = (account.id == entry.id)
                return applyMasking(to: updated)
            }
        }

        if let index = savedAccounts.firstIndex(where: { $0.id == entry.id }) {
            savedAccounts[index] = applyMasking(to: entry)
        } else {
            savedAccounts.append(applyMasking(to: entry))
        }
        try? accountDB.saveAccount(entry)
        if let authBlob, credentialBelongsToAccount(authBlob, accountId: entry.id) {
            try? accountDB.saveCredential(accountId: entry.id, authBlob: authBlob)
        }
        if entry.isCurrent {
            try? accountDB.setCurrentAccount(id: entry.id)
        }
        rescheduleAutoRefreshTasks()
    }

    private func persistRefreshedAccounts(_ accounts: [Account], currentAccountID: String?) {
        for account in accounts {
            try? accountDB.saveAccount(account)
            if let snapshot = account.usageSnapshot {
                try? accountDB.saveUsageSnapshot(accountId: account.id, snapshot: snapshot)
            }
        }

        if let currentAccountID {
            try? accountDB.setCurrentAccount(id: currentAccountID)
        }

        refreshCurrentAccountSelection()
    }

    private func transitionSnapshot() -> TransitionSnapshot {
        TransitionSnapshot(
            currentAccount: currentAccount,
            savedAccounts: savedAccounts,
            authBlob: try? accountStore.readAuthFile()
        )
    }

    private func rollbackTransition(accountID: String? = nil, to snapshot: TransitionSnapshot, error: String) {
        savedAccounts = applyMasking(to: snapshot.savedAccounts)
        currentAccount = snapshot.currentAccount.map { applyMasking(to: $0) }
        dashboardLoaded = true

        if let current = snapshot.currentAccount {
            if let restoredAuthBlob = snapshot.authBlob ?? loadCredential(for: current) {
                try? accountStore.writeAuthFile(restoredAuthBlob)
                try? accountDB.saveCredential(accountId: current.id, authBlob: restoredAuthBlob)
            }
            try? accountDB.saveAccount(current)
            try? accountDB.setCurrentAccount(id: current.id)
        }

        switchingAccountID = nil
        if let accountID {
            endRefreshingAccounts([accountID])
        }
        refreshing = false
        statusMessage = nil
        errorMessage = error
        rescheduleAutoRefreshTasks()
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

    private func loadCredential(for account: Account) -> AuthBlob? {
        return try? accountDB.loadCredential(accountId: account.id)
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
        var uniqueAccounts = savedAccounts
        if let current = currentAccount, !uniqueAccounts.contains(where: { $0.id == current.id }) {
            uniqueAccounts.append(current)
        }
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

    private func cancelAllAutoRefreshTasks() {
        for (_, task) in autoRefreshTasks {
            task.cancel()
        }
        autoRefreshTasks.removeAll()
        autoRefreshTargets.removeAll()
        autoRefreshFiredTargets.removeAll()
    }

    private func startFileWatching() {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let authPath = codexDir.appendingPathComponent("auth.json").path
        let prefsPath = accountStore.appSupportDirectoryURL
            .appendingPathComponent("preferences.json").path

        watchFile(at: authPath) { [weak self] in
            Task { @MainActor in
                guard let self, self.dashboardLoaded, self.switchingAccountID == nil else { return }
                NSLog("[CXSwitch] auth.json changed externally, reloading dashboard")
                await self.forceReloadDashboard()
            }
        }

        watchFile(at: prefsPath) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                NSLog("[CXSwitch] preferences.json changed externally, reloading preferences")
                if let prefs = try? self.accountStore.loadPreferences() {
                    self.preferences = prefs
                    self.applyPreferencesSideEffects()
                    self.applyTheme()
                    self.savedAccounts = self.applyMasking(to: self.savedAccounts)
                    if let current = self.currentAccount {
                        self.currentAccount = self.applyMasking(to: current)
                    }
                }
            }
        }
    }

    private func watchFile(at path: String, onChange: @escaping () -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[CXSwitch] Cannot watch file: %@", path)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler {
            onChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatchSources.append(source)
    }

    private func performAutoRefreshIfNeeded(accountID: String, targetDate: Date) async {
        guard let scheduledTarget = autoRefreshTargets[accountID], abs(scheduledTarget.timeIntervalSince(targetDate)) < 1 else {
            return
        }
        guard autoRefreshFiredTargets[accountID] != targetDate else { return }

        autoRefreshFiredTargets[accountID] = targetDate

        guard let account = savedAccounts.first(where: { $0.id == accountID })
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

    private func loadCurrentAccountForDashboard(authBlob: AuthBlob?) async -> Account? {
        do {
            if let current = try await fetchCurrentAccount(fromAuth: authBlob) {
                return current
            }
        } catch {
            NSLog("[CXSwitch] loadDashboard: current account fetch failed: %@", error.localizedDescription)
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return try? await fetchCurrentAccount(fromAuth: authBlob)
    }

    private func fetchCurrentAccount(fromAuth authBlob: AuthBlob?, expectedAccountId: String? = nil, fallbackEmail: String? = nil) async throws -> Account? {
        for attempt in 0..<3 {
            if let account = try await fetchCurrentAccountOnce(fromAuth: authBlob, expectedAccountId: expectedAccountId, fallbackEmail: fallbackEmail) {
                if let expectedAccountId, account.id != expectedAccountId, attempt < 2 {
                    try await restartStabilizationDelay(attempt: attempt)
                    continue
                }
                return account
            }
            if attempt < 2 {
                try await restartStabilizationDelay(attempt: attempt)
            }
        }
        return nil
    }

    private func fetchCurrentAccountOnce(fromAuth authBlob: AuthBlob?, expectedAccountId: String? = nil, fallbackEmail: String? = nil) async throws -> Account? {
        let response: AccountReadResponse = try await appServer.sendRequest(method: "account/read", params: AccountReadParams())
        let identity = authBlob.map(authIdentity(from:))
        let responseEmail = normalizedEmail(response.email)
        let authEmail = normalizedEmail(identity?.email)
        let fallbackIdentityEmail = normalizedEmail(fallbackEmail)
        let email = authEmail ?? responseEmail ?? fallbackIdentityEmail
        guard let email, !email.isEmpty else { return nil }

        if let authEmail, let responseEmail, authEmail != responseEmail {
            NSLog(
                "[CXSwitch] account/read returned stale email %@, expected %@ — server not ready",
                responseEmail,
                authEmail
            )
            return nil
        }

        let accountType = resolvedAccountType(response.accountType, authBlob: authBlob)
        let planType = PlanTypeMapper.from(response.planType) ?? planType(from: authBlob)
        let responseAccountId = normalizedAccountIdentifier(response.chatgptAccountId)
        let authAccountId = normalizedAccountIdentifier(identity?.chatgptAccountID ?? authBlob?.tokens?.accountId)
        let expectedIdentity = normalizedAccountIdentifier(expectedAccountId)
        let accountId = authAccountId ?? responseAccountId ?? expectedIdentity ?? email
        var account = Account(
            id: accountId,
            email: email,
            maskedEmail: email,
            accountType: accountType,
            planType: planType,
            chatgptAccountId: authAccountId ?? responseAccountId,
            addedAt: Date(),
            lastUsedAt: Date(),
            usageSnapshot: nil,
            usageError: nil,
            isCurrent: true
        )

        if let rateLimitsResponse: RateLimitsResponse = try? await appServer.sendRequest(method: "account/rateLimits/read", params: nil) {
            account.usageSnapshot = rateLimitsResponse.toUsageSnapshot()
        }

        account = applyMasking(to: account)
        return account
    }

    private func waitForAccountReady(authBlob: AuthBlob?, expectedAccountId: String? = nil, fallbackEmail: String? = nil) async -> Account? {
        var lastAccount: Account?
        for attempt in 1...5 {
            NSLog("[CXSwitch] waitForAccountReady: attempt %d", attempt)
            try? await Task.sleep(nanoseconds: stabilizationDelayNanoseconds(forAttempt: attempt - 1))

            if let account = try? await fetchCurrentAccountOnce(fromAuth: authBlob, expectedAccountId: expectedAccountId, fallbackEmail: fallbackEmail) {
                if let expectedAccountId, account.id != expectedAccountId {
                    NSLog("[CXSwitch] waitForAccountReady: got %@ but expected %@, retrying", account.id, expectedAccountId)
                    lastAccount = account
                    continue
                }
                return account
            }
        }
        // Return the last fetched account even if ID didn't match — the caller
        // (reconcileActiveAccountTransition) will verify the ID and rollback if needed.
        return lastAccount
    }

    private func refreshAccountUsage(_ account: Account, force: Bool) async -> (UsageSnapshot?, String?) {
        if !force, let updatedAt = account.usageSnapshot?.updatedAt {
            if Date().timeIntervalSince(updatedAt) < 60 {
                return (account.usageSnapshot, nil)
            }
        }

        do {
            guard let authBlob = loadCredential(for: account) else {
                return (nil, Strings.missingAuthForSelectedAccount)
            }

            let accessToken = authBlob.tokens?.accessToken
            let accountId = account.chatgptAccountId ?? authBlob.tokens?.accountId
            guard let accessToken, let accountId else {
                return (nil, Strings.missingToken)
            }

            NSLog("[CXSwitch] refreshUsage: probing %@ with chatgptAccountId=%@, tokenSuffix=...%@",
                  account.email, accountId, String(accessToken.suffix(8)))
            let snapshot = try await usageProbe.probeUsage(accessToken: accessToken, chatgptAccountId: accountId)
            NSLog("[CXSwitch] refreshUsage: %@ → primary=%.0f%% secondary=%.0f%%",
                  account.email, snapshot.primary?.usedPercent ?? -1, snapshot.secondary?.usedPercent ?? -1)
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

    private func persistAccountSnapshot(_ account: Account, updateCurrentAccount: Bool) {
        let existing = savedAccounts.first(where: { $0.id == account.id })
            ?? (currentAccount?.id == account.id ? currentAccount : nil)
        let merged = mergeAccountRecord(account, preserving: existing)
        NSLog("[CXSwitch] persistSnapshot: %@ (id=%@) updateCurrent=%d primary=%.0f%% current=%@",
              merged.email, String(merged.id.prefix(8)), updateCurrentAccount ? 1 : 0,
              merged.usageSnapshot?.primary?.usedPercent ?? -1,
              currentAccount?.email ?? "nil")

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
        try? accountDB.saveAccount(merged)
        if let snapshot = merged.usageSnapshot {
            try? accountDB.saveUsageSnapshot(accountId: merged.id, snapshot: snapshot)
        }
        if updateCurrentAccount || merged.isCurrent {
            try? accountDB.setCurrentAccount(id: merged.id)
        }
        rescheduleAutoRefreshTasks()
    }

    private func refreshCurrentAccountSelection() {
        guard let persistedCurrent = try? accountDB.currentAccount() else {
            return
        }

        if let refreshed = savedAccounts.first(where: { $0.id == persistedCurrent.id }) {
            currentAccount = applyMasking(to: refreshed)
        } else {
            currentAccount = applyMasking(to: persistedCurrent)
        }
    }

    private func canRepair(account: Account, with identity: AuthIdentity) -> Bool {
        if let currentAccountID = normalizedAccountIdentifier(identity.chatgptAccountID) {
            if normalizedAccountIdentifier(account.id) == currentAccountID
                || normalizedAccountIdentifier(account.chatgptAccountId) == currentAccountID {
                return true
            }
        }

        guard isLegacyEmailOnlyAccount(account), let email = normalizedEmail(identity.email) else {
            return false
        }

        return normalizedEmail(account.email) == email
    }

    private func enrichAccountMetadata(_ account: Account, authBlob: AuthBlob? = nil) -> Account {
        var updated = account
        let resolvedAuthBlob = authBlob
        let identity = resolvedAuthBlob.map(authIdentity(from:))

        if let authEmail = normalizedEmail(identity?.email), authEmail != normalizedEmail(updated.email) {
            updated.email = authEmail
            updated.maskedEmail = authEmail
        }

        if shouldBackfillAccountType(updated.accountType) {
            updated.accountType = AccountTypeMapper.from(authBlob: resolvedAuthBlob)
        }

        if updated.planType == nil {
            updated.planType = planType(from: resolvedAuthBlob)
        }

        if updated.chatgptAccountId == nil {
            updated.chatgptAccountId = chatgptAccountID(from: resolvedAuthBlob)
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

    private func normalizeSavedAccountsState() {
        let deduplicated = deduplicateAccounts(savedAccounts, preferredCurrentID: currentAccount?.id)
        let normalized = deduplicated.accounts

        savedAccounts = applyMasking(to: normalized)

        let currentMatch = normalized.first(where: { $0.id == currentAccount?.id })
            ?? normalized.first(where: \.isCurrent)
            ?? normalized.first
        if let currentMatch {
            currentAccount = applyMasking(to: currentMatch)
            savedAccounts = applyMasking(to: normalized.map { account in
                var updated = account
                updated.isCurrent = (account.id == currentMatch.id)
                return updated
            })
        } else {
            currentAccount = nil
        }
    }

    private func deduplicateAccounts(_ accounts: [Account], preferredCurrentID: String? = nil) -> (accounts: [Account], changed: Bool) {
        var orderedKeys: [String] = []
        var groups: [String: [Account]] = [:]

        for account in accounts {
            let key = canonicalAccountKey(for: account)
            if groups[key] == nil {
                orderedKeys.append(key)
                groups[key] = []
            }
            groups[key, default: []].append(account)
        }

        var changed = false
        var result: [Account] = []

        for key in orderedKeys {
            guard let group = groups[key], !group.isEmpty else { continue }
            if group.count == 1 {
                result.append(group[0])
                continue
            }

            changed = true
            let winner = group.max { lhs, rhs in
                accountDeduplicationScore(lhs, preferredCurrentID: preferredCurrentID) <
                    accountDeduplicationScore(rhs, preferredCurrentID: preferredCurrentID)
            } ?? group[0]

            var merged = winner
            for candidate in group where candidate.id != winner.id {
                merged = mergeAccountRecord(merged, preserving: candidate)
                if merged.chatgptAccountId == nil {
                    merged.chatgptAccountId = candidate.chatgptAccountId
                }
            }
            result.append(merged)
        }

        return (result, changed)
    }

    private func canonicalAccountKey(for account: Account) -> String {
        if let stableIdentity = stableAccountIdentity(for: account) {
            return "stable:\(stableIdentity)"
        }

        if let accountID = normalizedAccountIdentifier(account.chatgptAccountId) {
            return "chatgpt:\(accountID)"
        }
        return "id:\(account.id.lowercased())"
    }

    private func accountDeduplicationScore(_ account: Account, preferredCurrentID: String?) -> Int {
        var score = 0
        if account.id == preferredCurrentID {
            score += 10_000
        }
        if account.isCurrent {
            score += 5_000
        }
        if account.usageSnapshot != nil {
            score += 500
        }
        if account.chatgptAccountId != nil {
            score += 250
        }
        if account.lastUsedAt != nil {
            score += 125
        }
        return score
    }

    private func beginTransition() -> UInt64 {
        activeTransitionGeneration &+= 1
        activeTransitionTask?.cancel()
        return activeTransitionGeneration
    }

    private func preparedOptimisticAccount(from account: Account, authBlob: AuthBlob) -> Account {
        var prepared = enrichAccountMetadata(account, authBlob: authBlob)
        prepared.lastUsedAt = Date()
        prepared.isCurrent = true
        return prepared
    }

    private func provisionalImportedAccount(from authBlob: AuthBlob) -> Account? {
        let claims = JWTDecoder.decodePayload(authBlob.tokens?.idToken)
        let nested = claims?["https://api.openai.com/auth"] as? [String: Any]
        let email = (claims?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (nested?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? authBlob.tokens?.accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = nested?["chatgpt_account_id"] as? String
            ?? authBlob.tokens?.accountId
            ?? email

        guard let email, !email.isEmpty, let accountID, !accountID.isEmpty else {
            return nil
        }

        var provisional = Account(
            id: accountID,
            email: email,
            maskedEmail: email,
            accountType: AccountTypeMapper.from(authBlob: authBlob),
            planType: planType(from: authBlob),
            chatgptAccountId: chatgptAccountID(from: authBlob),
            addedAt: Date(),
            lastUsedAt: Date(),
            usageSnapshot: nil,
            usageError: nil,
            isCurrent: true
        )
        provisional = applyMasking(to: provisional)
        return provisional
    }

    private func optimisticallyActivateAccount(_ account: Account) {
        let merged = mergeAccountRecord(
            account,
            preserving: savedAccounts.first(where: { $0.id == account.id }) ?? (currentAccount?.id == account.id ? currentAccount : nil)
        )

        var listEntry = merged
        listEntry.isCurrent = false
        let masked = applyMasking(to: listEntry)
        if let index = savedAccounts.firstIndex(where: { $0.id == merged.id }) {
            savedAccounts[index] = masked
        } else {
            savedAccounts.append(masked)
        }

        var currentDisplay = merged
        currentDisplay.isCurrent = true
        currentAccount = applyMasking(to: displayAccountWithoutUsage(currentDisplay))
        dashboardLoaded = true
        rescheduleAutoRefreshTasks()
    }

    private func reconcileActiveAccountTransition(
        optimisticAccount: Account,
        authBlob: AuthBlob,
        previousState: TransitionSnapshot,
        generation: UInt64,
        successMessage: String,
        failureMessage: String
    ) async {
        defer {
            if activeTransitionGeneration == generation {
                activeTransitionTask = nil
            }
        }

        guard !Task.isCancelled else {
            if switchingAccountID == optimisticAccount.id {
                switchingAccountID = nil
            }
            endRefreshingAccounts([optimisticAccount.id])
            return
        }

        let expectedAccountID = optimisticAccount.chatgptAccountId ?? authBlob.tokens?.accountId
        let liveAccount = await waitForAccountReady(
            authBlob: authBlob,
            expectedAccountId: expectedAccountID,
            fallbackEmail: optimisticAccount.email
        )

        guard !Task.isCancelled else {
            if switchingAccountID == optimisticAccount.id {
                switchingAccountID = nil
            }
            endRefreshingAccounts([optimisticAccount.id])
            return
        }

        if activeTransitionGeneration != generation {
            if switchingAccountID == optimisticAccount.id {
                switchingAccountID = nil
            }
            endRefreshingAccounts([optimisticAccount.id])
            return
        }

        if var liveAccount {
            // Guard: if the live account ID doesn't match the expected target,
            // the app-server hasn't stabilized — treat as failure.
            if let expectedAccountID, liveAccount.id != expectedAccountID {
                NSLog("[CXSwitch] reconcile: live account ID %@ doesn't match expected %@, rolling back", liveAccount.id, expectedAccountID)
                rollbackTransition(accountID: optimisticAccount.id, to: previousState, error: failureMessage)
                return
            }

            // Strip usage from the live account — rateLimits/read may return
            // stale data from the previous session during an account switch.
            liveAccount.usageSnapshot = nil
            liveAccount.usageError = nil
            persistAccountSnapshot(liveAccount, updateCurrentAccount: true)
            showStatus(successMessage)

            // Fetch fresh usage with the new account's own credentials (from DB, not auth.json).
            // Hold switchingAccountID lock through the entire operation to block concurrent switches.
            let usageResult = await refreshAccountUsage(liveAccount, force: true)

            guard !Task.isCancelled, activeTransitionGeneration == generation else {
                if switchingAccountID == optimisticAccount.id {
                    switchingAccountID = nil
                }
                endRefreshingAccounts([optimisticAccount.id])
                return
            }

            let withUsage = applyUsageResult(to: liveAccount, result: usageResult)
            persistAccountSnapshot(withUsage, updateCurrentAccount: true)
        } else {
            rollbackTransition(accountID: optimisticAccount.id, to: previousState, error: failureMessage)
            return
        }

        if switchingAccountID == optimisticAccount.id {
            switchingAccountID = nil
        }
        endRefreshingAccounts([optimisticAccount.id])
    }

    private func repairAccountAuthMetadata(for account: Account, authBlob: AuthBlob) {
        let repaired = preparedOptimisticAccount(from: account, authBlob: authBlob)

        if let index = savedAccounts.firstIndex(where: { $0.id == repaired.id }) {
            savedAccounts[index] = applyMasking(to: repaired)
        } else {
            savedAccounts.append(applyMasking(to: repaired))
        }

        if currentAccount?.id == repaired.id {
            currentAccount = applyMasking(to: repaired)
        }
        try? accountDB.saveAccount(repaired)
        try? accountDB.saveCredential(accountId: repaired.id, authBlob: authBlob)
        if repaired.isCurrent {
            try? accountDB.setCurrentAccount(id: repaired.id)
        }
        rescheduleAutoRefreshTasks()
    }

    private func finishRepairLogin(for targetAccountID: String) async {
        guard let target = savedAccounts.first(where: { $0.id == targetAccountID })
            ?? (currentAccount?.id == targetAccountID ? currentAccount : nil) else {
            if switchingAccountID == targetAccountID {
                switchingAccountID = nil
            }
            await forceReloadDashboard()
            return
        }

        guard let authBlob = await readAuthFileWithRetry() else {
            errorMessage = Strings.missingAuthJSON
            if switchingAccountID == targetAccountID {
                switchingAccountID = nil
            }
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
            if switchingAccountID == targetAccountID {
                switchingAccountID = nil
            }
            await forceReloadDashboard()
            return
        }

        var liveAccount = try? await fetchCurrentAccount(fromAuth: authBlob, fallbackEmail: target.email)
        if liveAccount == nil {
            liveAccount = await waitForAccountReady(authBlob: authBlob, fallbackEmail: target.email)
        }
        let repaired = makeRepairedAccountRecord(target: target, liveAccount: liveAccount, authBlob: authBlob)
        replaceAccountRecord(target: target, with: repaired, authBlob: authBlob)
        showStatus(Strings.L("已修复 \(repaired.email)", en: "Repaired \(repaired.email)"))
        if switchingAccountID == targetAccountID {
            switchingAccountID = nil
        }
        await forceReloadDashboard()
    }

    private func makeRepairedAccountRecord(target: Account, liveAccount: Account?, authBlob: AuthBlob) -> Account {
        var repaired = liveAccount ?? target
        repaired.addedAt = target.addedAt
        repaired.lastUsedAt = Date()
        repaired.isCurrent = true
        repaired = enrichAccountMetadata(repaired, authBlob: authBlob)
        return repaired
    }

    private func replaceAccountRecord(target: Account, with replacement: Account, authBlob: AuthBlob?) {
        let targetIndex = savedAccounts.firstIndex(where: { $0.id == target.id })

        savedAccounts.removeAll { $0.id == target.id || $0.id == replacement.id }
        let maskedReplacement = applyMasking(to: replacement)
        if let targetIndex, targetIndex <= savedAccounts.count {
            savedAccounts.insert(maskedReplacement, at: targetIndex)
        } else {
            savedAccounts.append(maskedReplacement)
        }

        currentAccount = maskedReplacement
        markCurrentAccount(maskedReplacement)
        try? accountDB.saveAccount(replacement)
        if let authBlob {
            try? accountDB.saveCredential(accountId: replacement.id, authBlob: authBlob)
        }
        if let snapshot = replacement.usageSnapshot {
            try? accountDB.saveUsageSnapshot(accountId: replacement.id, snapshot: snapshot)
        }
        try? accountDB.setCurrentAccount(id: replacement.id)
        rescheduleAutoRefreshTasks()
    }

    private func userFacingUsageError(for error: Error) -> String? {
        if error is UsageProbeError {
            NSLog("[CXSwitch] usage probe failed: %@", String(describing: error))
            return nil
        }
        return error.localizedDescription
    }

    private func markCurrentAccount(_ current: Account) {
        savedAccounts = savedAccounts.map { account in
            var updated = account
            updated.isCurrent = (account.id == current.id)
            return updated
        }
    }

    private func activateAccount(_ account: Account, authBlob: AuthBlob?) {
        let existing = savedAccounts.first(where: { $0.id == account.id })
            ?? (currentAccount?.id == account.id ? currentAccount : nil)
        let active = mergeAccountRecord(account, preserving: existing)
        currentAccount = applyMasking(to: active)
        markCurrentAccount(active)
        dashboardLoaded = true
        persistAccount(active, authBlob: authBlob)
    }

    private func displayAccountWithoutUsage(_ account: Account) -> Account {
        var display = account
        display.usageSnapshot = nil
        display.usageError = nil
        return display
    }

    private func mergeAccountRecord(_ incoming: Account, preserving existing: Account?) -> Account {
        guard let existing, existing.id == incoming.id else { return incoming }

        var merged = incoming

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

    private func loadCachedAccounts() throws -> [Account] {
        let dbAccounts = try accountDB.loadAllAccounts()
        if !dbAccounts.isEmpty {
            return dbAccounts
        }
        return []
    }

    private func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    private func credentialBelongsToAccount(_ authBlob: AuthBlob, accountId: String) -> Bool {
        let identity = authIdentity(from: authBlob)
        let credentialAccountId = normalizedAccountIdentifier(identity.chatgptAccountID)
            ?? normalizedAccountIdentifier(authBlob.tokens?.accountId)
        let targetAccountId = normalizedAccountIdentifier(accountId)
        guard let credentialAccountId, let targetAccountId else { return true }
        return credentialAccountId == targetAccountId
    }

    private func normalizedAccountIdentifier(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    private func stableAccountIdentity(for account: Account) -> String? {
        if let accountID = normalizedAccountIdentifier(account.chatgptAccountId) {
            return accountID
        }

        let normalizedID = normalizedAccountIdentifier(account.id)
        if let normalizedID, !normalizedID.contains("@") {
            return normalizedID
        }

        return nil
    }

    private func isLegacyEmailOnlyAccount(_ account: Account) -> Bool {
        guard stableAccountIdentity(for: account) == nil else { return false }
        return normalizedEmail(account.id) == normalizedEmail(account.email)
    }

    private func applyPreferencesSideEffects() {
        Strings.languageProvider = { [weak self] in
            self?.preferences.language ?? Preferences.defaultLanguage
        }
    }

    private func applyTheme() {
        switch normalizedThemeValue(preferences.theme) {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    private func normalizedThemeValue(_ theme: String?) -> String {
        switch theme?.lowercased() {
        case "light", "dark", "system":
            return theme?.lowercased() ?? Preferences.defaultTheme
        default:
            return Preferences.defaultTheme
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

    private func restartStabilizationDelay(attempt: Int = 0) async throws {
        try await Task.sleep(nanoseconds: stabilizationDelayNanoseconds(forAttempt: attempt))
    }

    private func stabilizationDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let delays: [UInt64] = [
            200_000_000,
            400_000_000,
            800_000_000,
            1_200_000_000,
            1_600_000_000
        ]
        return delays[min(max(attempt, 0), delays.count - 1)]
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
