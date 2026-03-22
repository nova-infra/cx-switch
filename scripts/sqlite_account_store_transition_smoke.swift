import Foundation
import AppKit

@MainActor
@main
struct SQLiteAccountStoreTransitionSmoke {
    static func main() async throws {
        let _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cxswitch-sqlite-transition-smoke-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let codexAuthURL = root.appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)

        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let store = try AccountStore(
            appSupportURL: support,
            codexAuthURL: codexAuthURL
        )
        let db = try AccountDatabase(appSupportURL: support)
        let keychain = NoopKeychain()
        let server = FakeCodexAppServer()
        let authService = FakeAuthService()
        let state = AppState(
            accountStore: store,
            accountDB: db,
            legacyKeychainService: keychain,
            appServer: server,
            usageProbe: UsageProbe(),
            authService: authService
        )

        let currentAuth = makeAuthBlob(
            email: "current@example.com",
            accountID: "current-account",
            planType: "team",
            refreshToken: "refresh-current",
            accessToken: "access-current"
        )
        let switchAuth = makeAuthBlob(
            email: "switch@example.com",
            accountID: "switch-account",
            planType: "plus",
            refreshToken: "refresh-switch",
            accessToken: "access-switch"
        )
        let importedAuth = makeAuthBlob(
            email: "imported@example.com",
            accountID: "imported-account",
            planType: "pro",
            refreshToken: "refresh-import",
            accessToken: "access-import"
        )

        let currentAccount = makeAccount(
            id: "current-account",
            email: "current@example.com",
            authType: .oauth,
            planType: .team,
            isCurrent: true
        )
        let switchAccount = makeAccount(
            id: "switch-account",
            email: "switch@example.com",
            authType: .oauth,
            planType: .plus,
            isCurrent: false
        )

        try db.saveAccount(currentAccount)
        try db.saveCredential(accountId: currentAccount.id, authBlob: currentAuth)
        try db.setCurrentAccount(id: currentAccount.id)
        try db.saveAccount(switchAccount)
        try db.saveCredential(accountId: switchAccount.id, authBlob: switchAuth)
        try store.writeAuthFile(currentAuth)

        server.setCurrentAccountResponse(
            email: currentAccount.email,
            planType: "team",
            accountType: "oauth"
        )

        authService.setTokens(
            for: "refresh-import",
            tokens: importedAuth.tokens ?? AuthTokens()
        )

        await state.loadDashboard()
        assert(state.currentAccount?.id == currentAccount.id, "dashboard should load current account")

        server.setAccountReadBehavior(.delayedSuccess(delayNanoseconds: 350_000_000))
        server.setCurrentAccountResponse(
            email: switchAccount.email,
            planType: "plus",
            accountType: "oauth"
        )

        let switchStart = Date()
        await state.switchAccount(to: switchAccount)
        let switchElapsed = Date().timeIntervalSince(switchStart)
        assert(switchElapsed < 0.2, "switch should update optimistically")
        assert(state.currentAccount?.id == switchAccount.id, "switch should update UI immediately")

        try await Task.sleep(nanoseconds: 900_000_000)
        assert(state.currentAccount?.id == switchAccount.id, "switch should stay on target after live refresh")

        authService.setTokens(
            for: "refresh-import",
            tokens: importedAuth.tokens ?? AuthTokens()
        )
        server.setCurrentAccountResponse(
            email: "imported@example.com",
            planType: "pro",
            accountType: "oauth"
        )

        let importStart = Date()
        await state.importRefreshToken("refresh-import")
        let importElapsed = Date().timeIntervalSince(importStart)
        assert(importElapsed < 0.2, "import should display optimistically")
        assert(state.currentAccount?.id == "imported-account", "import should show imported account immediately")

        for _ in 0..<20 {
            if state.switchingAccountID == nil {
                break
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        assert(state.switchingAccountID == nil, "import transition should settle before rollback test")

        let failingAccount = makeAccount(
            id: "failing-account",
            email: "fail@example.com",
            authType: .oauth,
            planType: .team,
            isCurrent: false
        )
        try db.saveAccount(failingAccount)
        try db.saveCredential(accountId: failingAccount.id, authBlob: makeAuthBlob(
            email: failingAccount.email,
            accountID: failingAccount.id,
            planType: "team",
            refreshToken: "refresh-fail",
            accessToken: "access-fail"
        ))

        server.setAccountReadBehavior(.alwaysFail)
        let rollbackStart = Date()
        await state.switchAccount(to: failingAccount)
        try await Task.sleep(nanoseconds: 7_500_000_000)
        let rollbackElapsed = Date().timeIntervalSince(rollbackStart)
        assert(rollbackElapsed >= 7.0, "rollback path should exercise retry window")
        print("rollback current:", state.currentAccount?.id ?? "nil")
        print("rollback saved:", state.savedAccounts.map(\.id))
        print("rollback status:", state.statusMessage ?? "nil")
        print("rollback error:", state.errorMessage ?? "nil")
        assert(state.currentAccount?.id == "imported-account", "failed sync should roll back to previous account")
        assert(state.errorMessage?.contains("restored") == true || state.errorMessage?.contains("恢复") == true, "rollback should surface an error")

        print("SMOKE_OK")
    }
}

private enum FakeServerMode {
    case delayedSuccess(delayNanoseconds: UInt64)
    case alwaysFail
}

private final class FakeCodexAppServer: CodexAppServering, @unchecked Sendable {
    private var notificationHandler: ((ServerNotification) -> Void)?
    private var mode: FakeServerMode = .delayedSuccess(delayNanoseconds: 0)
    private var currentAccountResponse: [String: Any] = [:]
    private let encoder = JSONEncoder()

    func setAccountReadBehavior(_ mode: FakeServerMode) {
        self.mode = mode
    }

    func setCurrentAccountResponse(email: String, planType: String, accountType: String) {
        currentAccountResponse = [
            "account": [
                "type": accountType,
                "email": email,
                "planType": planType
            ],
            "requiresOpenaiAuth": false
        ]
    }

    func start() throws {}
    func shutdown() {}
    func restart() throws {}
    func restartAndInitialize() async throws {}
    func setNotificationHandler(_ handler: ((ServerNotification) -> Void)?) { notificationHandler = handler }
    func initialize(clientName: String, version: String) async throws {}

    func sendRequest<T: Decodable>(method: String, params: Encodable? = nil) async throws -> T {
        switch method {
        case "account/read":
            switch mode {
            case .alwaysFail:
                throw CodexAppServerError.responseError(code: 500, message: "simulated failure")
            case .delayedSuccess(let delayNanoseconds):
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                return try decodeCurrentResponse(as: T.self)
            }
        case "account/rateLimits/read":
            return try decodeRateLimitsResponse(as: T.self)
        case "account/login/start":
            return try decodeJSON(["loginId": "login-1", "authUrl": "https://example.com/login"], as: T.self)
        case "account/login/cancel":
            return try decodeJSON([String: String](), as: T.self)
        case "initialize":
            return try decodeJSON([String: String](), as: T.self)
        default:
            return try decodeJSON([String: String](), as: T.self)
        }
    }

    func sendNotification(method: String, params: Encodable? = nil) throws {
        _ = notificationHandler
    }

    private func decodeCurrentResponse<T: Decodable>(as type: T.Type) throws -> T {
        return try decodeJSON(currentAccountResponse, as: T.self)
    }

    private func decodeRateLimitsResponse<T: Decodable>(as type: T.Type) throws -> T {
        let payload: [String: Any] = [
            "rateLimits": [
                "limitId": "codex",
                "planType": "plus",
                "primary": [
                    "usedPercent": 28.0,
                    "resetsAt": Date().addingTimeInterval(3600).timeIntervalSince1970,
                    "windowDurationMins": 300
                ],
                "secondary": [
                    "usedPercent": 12.0,
                    "resetsAt": Date().addingTimeInterval(86400).timeIntervalSince1970,
                    "windowDurationMins": 10080
                ]
            ]
        ]
        return try decodeJSON(payload, as: T.self)
    }

    private func decodeJSON<T: Decodable>(_ object: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private final class FakeAuthService: AuthTokenExchanging, @unchecked Sendable {
    private var tokensByRefreshToken: [String: AuthTokens] = [:]

    func setTokens(for refreshToken: String, tokens: AuthTokens) {
        tokensByRefreshToken[refreshToken] = tokens
    }

    func exchangeRefreshToken(_ refreshToken: String) async throws -> AuthTokens {
        if let tokens = tokensByRefreshToken[refreshToken] {
            return tokens
        }
        throw NSError(domain: "FakeAuthService", code: 1)
    }
}

private final class NoopKeychain: KeychainStoring, @unchecked Sendable {
    func saveAuthBlob(_ blob: AuthBlob, accountId: String) throws {}
    func loadAuthBlob(accountId: String) throws -> AuthBlob? { nil }
    func deleteAuthBlob(accountId: String) throws {}
}

private func makeAccount(
    id: String,
    email: String,
    authType: AccountType,
    planType: PlanType,
    isCurrent: Bool
) -> Account {
    Account(
        id: id,
        email: email,
        maskedEmail: email,
        accountType: authType,
        planType: planType,
        chatgptAccountId: id,
        addedAt: Date(),
        lastUsedAt: Date(),
        usageSnapshot: nil,
        usageError: nil,
        isCurrent: isCurrent
    )
}

private func makeAuthBlob(
    email: String,
    accountID: String,
    planType: String,
    refreshToken: String,
    accessToken: String
) -> AuthBlob {
    let payload: [String: Any] = [
        "email": email,
        "https://api.openai.com/auth": [
            "chatgpt_account_id": accountID,
            "chatgpt_plan_type": planType
        ]
    ]
    let idToken = makeJWT(payload: payload)
    return AuthBlob(
        authMode: "chatgpt",
        lastRefresh: ISO8601DateFormatter().string(from: Date()),
        tokens: AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountId: accountID
        ),
        openaiApiKey: nil
    )
}

private func makeJWT(payload: [String: Any]) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let headerData = try! jsonData(from: header)
    let payloadData = try! jsonData(from: payload)
    return "\(base64URL(headerData)).\(base64URL(payloadData)).sig"
}

private func jsonData(from object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [])
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
