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
    var errorMessage: String?

    nonisolated(unsafe) private let accountStore: AccountStore
    nonisolated(unsafe) private let keychainService: any KeychainStoring
    private let appServer: CodexAppServer
    nonisolated(unsafe) private let usageProbe: UsageProbe
    nonisolated(unsafe) private let authService: AuthService
    private var pendingLoginId: String?
    private var dashboardLoading = false

    init(
        accountStore: AccountStore = try! AccountStore(),
        keychainService: any KeychainStoring = KeychainService(),
        appServer: CodexAppServer = CodexAppServer(),
        usageProbe: UsageProbe = UsageProbe(),
        authService: AuthService = AuthService()
    ) {
        self.accountStore = accountStore
        self.keychainService = keychainService
        self.appServer = appServer
        self.usageProbe = usageProbe
        self.authService = authService
        self.pendingLoginId = nil

        self.currentAccount = nil
        self.savedAccounts = []
        self.preferences = Preferences()
        self.loginFlow = LoginFlowState.empty()
        self.refreshing = false
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
        guard !dashboardLoading else { return }
        dashboardLoading = true
        defer { dashboardLoading = false }
        errorMessage = nil
        do {
            NSLog("[CXSwitch] loadDashboard: starting app server...")
            try await startAppServerIfNeeded()
            NSLog("[CXSwitch] loadDashboard: initializing...")
            try await appServer.initialize()
            NSLog("[CXSwitch] loadDashboard: initialized")

            let prefs = try accountStore.loadPreferences()
            preferences = prefs
            applyPreferencesSideEffects()
            NSLog("[CXSwitch] loadDashboard: prefs loaded, maskEmails=%@", String(describing: prefs.maskEmails))

            let registry = try accountStore.loadRegistry()
            savedAccounts = applyMasking(to: registry)
            NSLog("[CXSwitch] loadDashboard: registry loaded, %d accounts", registry.count)

            if let current = try await fetchCurrentAccount() {
                currentAccount = current
                markCurrentAccount(current)
                NSLog("[CXSwitch] loadDashboard: current account = %@", current.email)
                // Auto-persist current account to registry + keychain
                await persistAccount(current)
            } else {
                currentAccount = nil
                NSLog("[CXSwitch] loadDashboard: no current account")
            }

            Task { [weak self] in
                await self?.refreshSavedAccounts(force: false)
            }
        } catch {
            NSLog("[CXSwitch] loadDashboard error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(to account: Account) async {
        errorMessage = nil
        do {
            var authBlob: AuthBlob?

            // Try keychain first
            if let keychainKey = account.authKeychainKey {
                authBlob = try keychainService.loadAuthBlob(accountId: keychainKey)
            }

            // Fallback: restore from registry stored auth
            if authBlob == nil, let storedAuth = account.storedAuth {
                authBlob = decodeStoredAuth(storedAuth)
            }

            guard let authBlob else {
                errorMessage = Strings.missingAuthForSelectedAccount
                return
            }

            try accountStore.writeAuthFile(authBlob)
            try appServer.restart()
            try await restartStabilizationDelay()
            await loadDashboard()
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
            let accountId = current.authKeychainKey ?? current.id
            try keychainService.saveAuthBlob(authBlob, accountId: accountId)

            current.authKeychainKey = accountId
            current.lastUsedAt = Date()

            if !savedAccounts.contains(where: { $0.id == current.id }) {
                savedAccounts.append(current)
            } else {
                savedAccounts = savedAccounts.map { $0.id == current.id ? current : $0 }
            }
            savedAccounts = applyMasking(to: savedAccounts)
            try accountStore.saveRegistry(savedAccounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAccount(_ account: Account) async {
        errorMessage = nil
        do {
            let keychainKey = account.authKeychainKey ?? account.id
            try keychainService.deleteAuthBlob(accountId: keychainKey)
            savedAccounts.removeAll { $0.id == account.id }
            try accountStore.saveRegistry(savedAccounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSavedAccounts(force: Bool) async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }

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
        do {
            try accountStore.saveRegistry(savedAccounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAddAccount() async {
        errorMessage = nil
        do {
            try await startAppServerIfNeeded()
            try await appServer.initialize()
            let response: LoginStartResponse = try await appServer.sendRequest(
                method: "account/login/start",
                params: LoginStartParams()
            )

            pendingLoginId = response.loginId
            loginFlow = LoginFlowState(
                active: true,
                loginId: response.loginId,
                authUrl: response.authUrl,
                status: Strings.loginWaiting,
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
            loginFlow = LoginFlowState.empty()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importRefreshToken(_ rawToken: String) async {
        errorMessage = nil
        let token = sanitizeToken(rawToken)
        guard !token.isEmpty else {
            errorMessage = Strings.invalidRefreshToken
            return
        }

        refreshing = true
        NSLog("[CXSwitch] importRefreshToken: exchanging token...")
        do {
            let tokens = try await authService.exchangeRefreshToken(token)
            NSLog("[CXSwitch] importRefreshToken: exchange OK, writing auth.json...")
            let authBlob = AuthBlob(
                authMode: "refresh_token",
                lastRefresh: ISO8601DateFormatter().string(from: Date()),
                tokens: tokens,
                openaiApiKey: nil
            )

            try accountStore.writeAuthFile(authBlob)
            appServer.shutdown()

            // Restart with retry — wait for app-server to be ready
            for attempt in 1...3 {
                NSLog("[CXSwitch] importRefreshToken: restart attempt %d...", attempt)
                try await restartStabilizationDelay()
                try appServer.start()
                try await appServer.initialize()

                if let account = try? await fetchCurrentAccountOnce(fromAuth: authBlob) {
                    NSLog("[CXSwitch] importRefreshToken: got account %@", account.email)
                    currentAccount = account
                    markCurrentAccount(account)
                    await persistAccount(account)
                    refreshing = false
                    return
                }
                appServer.shutdown()
            }

            // Final fallback: just reload
            refreshing = false
            dashboardLoading = false
            await loadDashboard()
            NSLog("[CXSwitch] importRefreshToken: done, current=%@", currentAccount?.email ?? "nil")
        } catch {
            refreshing = false
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

    func setSaveToKeychain(_ enabled: Bool) {
        preferences.saveToKeychain = enabled
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
        do {
            var entry = account
            let keychainKey = entry.authKeychainKey ?? entry.id

            if let authBlob = try accountStore.readAuthFile() {
                if preferences.saveToKeychain == true {
                    // Keychain mode: save encrypted, clear plaintext
                    try keychainService.saveAuthBlob(authBlob, accountId: keychainKey)
                    entry.authKeychainKey = keychainKey
                    entry.storedAuth = nil
                } else {
                    // File mode: save Base64 in registry, skip keychain
                    entry.storedAuth = encodeStoredAuth(authBlob)
                    entry.authKeychainKey = nil
                }
            }

            // Upsert into registry
            if let index = savedAccounts.firstIndex(where: { $0.id == entry.id }) {
                savedAccounts[index] = applyMasking(to: entry)
            } else {
                savedAccounts.append(applyMasking(to: entry))
            }
            try accountStore.saveRegistry(savedAccounts)
        } catch {
            NSLog("[CXSwitch] persistAccount error: %@", error.localizedDescription)
        }
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

    private func fetchCurrentAccount(fromAuth authBlob: AuthBlob?, expectedAccountId: String? = nil) async throws -> Account? {
        for attempt in 0..<3 {
            if let account = try await fetchCurrentAccountOnce(fromAuth: authBlob) {
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

    private func fetchCurrentAccountOnce(fromAuth authBlob: AuthBlob?) async throws -> Account? {
        let response: AccountReadResponse = try await appServer.sendRequest(method: "account/read", params: AccountReadParams())
        guard let email = response.email else { return nil }

        let planType = PlanTypeMapper.from(response.planType)
        let accountId = response.chatgptAccountId ?? authBlob?.tokens?.accountId ?? email
        var account = Account(
            id: accountId,
            email: email,
            maskedEmail: email,
            planType: planType,
            chatgptAccountId: response.chatgptAccountId ?? authBlob?.tokens?.accountId,
            addedAt: Date(),
            lastUsedAt: Date(),
            usageSnapshot: nil,
            authKeychainKey: accountId,
            usageError: nil,
            isCurrent: true
        )

        if let rateLimitsResponse: RateLimitsResponse = try? await appServer.sendRequest(method: "account/rateLimits/read", params: nil) {
            account.usageSnapshot = rateLimitsResponse.toUsageSnapshot()
        }

        account = applyMasking(to: account)
        return account
    }

    private func refreshAccountUsage(_ account: Account, force: Bool) async -> (UsageSnapshot?, String?) {
        if !force, let updatedAt = account.usageSnapshot?.updatedAt {
            if Date().timeIntervalSince(updatedAt) < 60 {
                return (account.usageSnapshot, nil)
            }
        }

        do {
            var authBlob: AuthBlob?
            if let keychainKey = account.authKeychainKey {
                authBlob = try keychainService.loadAuthBlob(accountId: keychainKey)
            }
            if authBlob == nil, let storedAuth = account.storedAuth {
                authBlob = decodeStoredAuth(storedAuth)
            }
            guard let authBlob else {
                return (nil, Strings.missingAuth)
            }

            let accessToken = authBlob.tokens?.accessToken
            let accountId = account.chatgptAccountId ?? authBlob.tokens?.accountId
            guard let accessToken, let accountId else {
                return (nil, Strings.missingToken)
            }

            let snapshot = try await usageProbe.probeUsage(accessToken: accessToken, chatgptAccountId: accountId)
            return (snapshot, nil)
        } catch {
            return (nil, error.localizedDescription)
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

    private func markCurrentAccount(_ current: Account) {
        savedAccounts = savedAccounts.map { account in
            var updated = account
            updated.isCurrent = (account.id == current.id)
            return updated
        }
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
        loginFlow.status = Strings.loginCompleted
        loginFlow.message = nil
        loginFlow.error = nil
        loginFlow.completedAt = Date()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadDashboard()
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
        return PlanType(rawValue: normalized) ?? .unknown
    }
}
