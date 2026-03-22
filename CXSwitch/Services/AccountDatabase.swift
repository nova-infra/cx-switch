import Foundation
import SQLite3

enum AccountDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case executionFailed(String)
    case migrationFailed(String)
    case missingDatabaseRow

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "无法打开账号数据库：\(message)"
        case let .executionFailed(message):
            return "账号数据库执行失败：\(message)"
        case let .migrationFailed(message):
            return "账号迁移失败：\(message)"
        case .missingDatabaseRow:
            return "账号数据库记录缺失"
        }
    }
}

final class AccountDatabase {
    private let fileManager: FileManager
    private let appSupportURL: URL
    private let dbURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.novainfra.cx-switch.account-database", qos: .utility)
    private let didCreateDatabase: Bool
    private var db: OpaquePointer?

    private let migratedRegistryFilename = "registry.json.migrated"

    init(
        fileManager: FileManager = .default,
        appSupportURL: URL? = nil,
        dbURL: URL? = nil
    ) throws {
        self.fileManager = fileManager

        if let appSupportURL {
            self.appSupportURL = appSupportURL
        } else {
            guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw AccountDatabaseError.openFailed("缺少 Application Support 目录")
            }
            self.appSupportURL = base.appendingPathComponent("com.novainfra.cx-switch", isDirectory: true)
        }

        if let dbURL {
            self.dbURL = dbURL
        } else {
            self.dbURL = self.appSupportURL.appendingPathComponent("cx-switch.db", isDirectory: false)
        }

        self.didCreateDatabase = !fileManager.fileExists(atPath: self.dbURL.path)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try ensureAppSupportDirectory()
        try openDatabase()
        try createSchemaIfNeeded()
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    func migrateIfNeeded(registryPath: String, keychainService: KeychainStoring? = nil) throws {
        guard didCreateDatabase else { return }

        let registryURL = URL(fileURLWithPath: registryPath)
        guard fileManager.fileExists(atPath: registryURL.path) else { return }

        let migratedMarkerURL = registryURL.deletingLastPathComponent().appendingPathComponent(migratedRegistryFilename)
        guard !fileManager.fileExists(atPath: migratedMarkerURL.path) else { return }

        let legacyAccounts = try loadLegacyRegistryAccounts(from: registryURL)
        if legacyAccounts.isEmpty {
            return
        }

        try writeTransaction {
            for legacy in legacyAccounts {
                let account = legacy.toAccount()
                try self.saveAccountLocked(account)

                if let storedAuth = legacy.storedAuth, let authBlob = self.decodeStoredAuthBase64(storedAuth) {
                    try self.saveCredentialLocked(accountId: account.id, authBlob: authBlob)
                }

                if let keychainService, let keychainKey = legacy.authKeychainKey {
                    if let authBlob = try keychainService.loadAuthBlob(accountId: keychainKey)
                        ?? keychainService.loadAuthBlob(accountId: account.id) {
                        try self.saveCredentialLocked(accountId: account.id, authBlob: authBlob)
                    }
                }

                if let snapshot = legacy.usageSnapshot {
                    try self.saveUsageSnapshotLocked(accountId: account.id, snapshot: snapshot)
                }
            }

            if let current = legacyAccounts.first(where: { $0.isCurrent == true }) {
                try self.setCurrentAccountLocked(id: current.id)
            }
        }

        if fileManager.fileExists(atPath: migratedMarkerURL.path) {
            try? fileManager.removeItem(at: migratedMarkerURL)
        }
        try fileManager.moveItem(at: registryURL, to: migratedMarkerURL)
    }

    func migrateIfNeeded(accountStore: AccountStore, keychainService: KeychainStoring? = nil) throws {
        try migrateIfNeeded(
            registryPath: accountStore.registryFileURL.path,
            keychainService: keychainService
        )
    }

    func loadAllAccounts() throws -> [Account] {
        try queue.sync {
            try loadAllAccountsLocked()
        }
    }

    func saveAccount(_ account: Account) throws {
        try queue.sync {
            try writeTransaction {
                try self.saveAccountLocked(account)
            }
        }
    }

    func deleteAccount(id: String) throws {
        try queue.sync {
            try writeTransaction {
                try self.deleteAccountLocked(id: id)
            }
        }
    }

    func currentAccount() throws -> Account? {
        try queue.sync {
            let accounts = try loadAllAccountsLocked()
            return accounts.first(where: { $0.isCurrent }) ?? accounts.first
        }
    }

    func setCurrentAccount(id: String) throws {
        try queue.sync {
            try writeTransaction {
                try self.setCurrentAccountLocked(id: id)
            }
        }
    }

    func saveCredential(accountId: String, authBlob: AuthBlob) throws {
        try queue.sync {
            try writeTransaction {
                try self.saveCredentialLocked(accountId: accountId, authBlob: authBlob)
            }
        }
    }

    func loadCredential(accountId: String) throws -> AuthBlob? {
        try queue.sync { () throws -> AuthBlob? in
            guard let data = try rawCredentialBlob(accountId: accountId) else {
                return nil
            }
            return try decodeAuthBlob(from: data)
        }
    }

    func deleteCredential(accountId: String) throws {
        try queue.sync {
            try writeTransaction {
                try self.deleteRowLocked(table: "credentials", accountId: accountId)
            }
        }
    }

    func saveUsageSnapshot(accountId: String, snapshot: UsageSnapshot) throws {
        try queue.sync {
            try writeTransaction {
                try self.saveUsageSnapshotLocked(accountId: accountId, snapshot: snapshot)
            }
        }
    }

    func loadUsageSnapshot(accountId: String) throws -> UsageSnapshot? {
        try queue.sync { () throws -> UsageSnapshot? in
            guard let data = try rawUsageSnapshot(accountId: accountId) else {
                return nil
            }
            return try decoder.decode(UsageSnapshot.self, from: data)
        }
    }

    func saveAccountsSnapshot(_ accounts: [Account]) throws {
        try queue.sync {
            try writeTransaction {
                for account in accounts {
                    try self.saveAccountLocked(account)
                    if let usageSnapshot = account.usageSnapshot {
                        try self.saveUsageSnapshotLocked(accountId: account.id, snapshot: usageSnapshot)
                    }
                }
                if let current = accounts.first(where: { $0.isCurrent }) {
                    try self.setCurrentAccountLocked(id: current.id)
                }
            }
        }
    }

    private struct LegacyRegistryFile: Codable {
        let version: Int?
        let accounts: [LegacyAccount]
    }

    private struct LegacyAccount: Codable {
        let id: String
        var email: String
        var maskedEmail: String?
        var accountType: AccountType?
        var planType: PlanType?
        var chatgptAccountId: String?
        var addedAt: Date?
        var lastUsedAt: Date?
        var usageSnapshot: UsageSnapshot?
        var authKeychainKey: String?
        var storedAuth: String?
        var usageError: String?
        var isCurrent: Bool?

        func toAccount() -> Account {
            Account(
                id: id,
                email: email,
                maskedEmail: maskedEmail ?? email,
                accountType: accountType,
                planType: planType,
                chatgptAccountId: chatgptAccountId,
                addedAt: addedAt ?? Date(),
                lastUsedAt: lastUsedAt,
                usageSnapshot: usageSnapshot,
                usageError: usageError,
                isCurrent: isCurrent ?? false
            )
        }
    }

    private func openDatabase() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(dbURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle {
                sqlite3_close_v2(handle)
            }
            throw AccountDatabaseError.openFailed(message)
        }

        db = handle
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func createSchemaIfNeeded() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            email TEXT NOT NULL,
            masked_email TEXT NOT NULL,
            account_type TEXT,
            plan_type TEXT,
            chatgpt_account_id TEXT,
            added_at REAL NOT NULL,
            last_used_at REAL,
            is_current INTEGER NOT NULL DEFAULT 0,
            usage_error TEXT
        );
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS credentials (
            account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
            auth_blob TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS usage_snapshots (
            account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
            snapshot_json TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
    }

    private func loadAllAccountsLocked() throws -> [Account] {
        let sql = """
        SELECT
            a.id,
            a.email,
            a.masked_email,
            a.account_type,
            a.plan_type,
            a.chatgpt_account_id,
            a.added_at,
            a.last_used_at,
            a.is_current,
            a.usage_error,
            u.snapshot_json
        FROM accounts a
        LEFT JOIN usage_snapshots u ON u.account_id = a.id
        ORDER BY a.is_current DESC, a.added_at ASC;
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        var results: [Account] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                results.append(try account(from: stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw errorFromDB("loadAllAccounts")
            }
        }

        return results
    }

    private func saveAccountLocked(_ account: Account) throws {
        let sql = """
        INSERT INTO accounts (
            id, email, masked_email, account_type, plan_type, chatgpt_account_id,
            added_at, last_used_at, is_current, usage_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            email = excluded.email,
            masked_email = excluded.masked_email,
            account_type = excluded.account_type,
            plan_type = excluded.plan_type,
            chatgpt_account_id = excluded.chatgpt_account_id,
            added_at = excluded.added_at,
            last_used_at = excluded.last_used_at,
            is_current = excluded.is_current,
            usage_error = excluded.usage_error;
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        try bind(account.id, at: 1, to: stmt)
        try bind(account.email, at: 2, to: stmt)
        try bind(account.maskedEmail, at: 3, to: stmt)
        try bind(account.accountType?.rawValue, at: 4, to: stmt)
        try bind(account.planType?.rawValue, at: 5, to: stmt)
        try bind(account.chatgptAccountId, at: 6, to: stmt)
        try bind(account.addedAt.timeIntervalSince1970, at: 7, to: stmt)
        try bind(account.lastUsedAt?.timeIntervalSince1970, at: 8, to: stmt)
        try bind(account.isCurrent ? 1 : 0, at: 9, to: stmt)
        try bind(account.usageError, at: 10, to: stmt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw errorFromDB("saveAccount")
        }
    }

    private func deleteAccountLocked(id: String) throws {
        let stmt = try prepare("DELETE FROM accounts WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }

        try bind(id, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw errorFromDB("deleteAccount")
        }
    }

    private func setCurrentAccountLocked(id: String) throws {
        let stmt = try prepare("""
        UPDATE accounts
        SET is_current = CASE WHEN id = ? THEN 1 ELSE 0 END;
        """)
        defer { sqlite3_finalize(stmt) }

        try bind(id, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw errorFromDB("setCurrentAccount")
        }
    }

    private func saveCredentialLocked(accountId: String, authBlob: AuthBlob) throws {
        let stmt = try prepare("""
        INSERT INTO credentials (account_id, auth_blob, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(account_id) DO UPDATE SET
            auth_blob = excluded.auth_blob,
            updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }

        try bind(accountId, at: 1, to: stmt)
        try bindRawAuthBlob(authBlob, at: 2, to: stmt)
        try bind(Date().timeIntervalSince1970, at: 3, to: stmt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw errorFromDB("saveCredential")
        }
    }

    private func saveUsageSnapshotLocked(accountId: String, snapshot: UsageSnapshot) throws {
        let stmt = try prepare("""
        INSERT INTO usage_snapshots (account_id, snapshot_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(account_id) DO UPDATE SET
            snapshot_json = excluded.snapshot_json,
            updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }

        try bind(accountId, at: 1, to: stmt)
        try bindRawJSON(snapshot, at: 2, to: stmt)
        try bind(Date().timeIntervalSince1970, at: 3, to: stmt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw errorFromDB("saveUsageSnapshot")
        }
    }

    private func loadCredentialLocked(accountId: String) throws -> AuthBlob? {
        guard let data = try rawCredentialBlob(accountId: accountId) else {
            return nil
        }
        return try decodeAuthBlob(from: data)
    }

    private func loadUsageSnapshotLocked(accountId: String) throws -> UsageSnapshot? {
        guard let data = try rawUsageSnapshot(accountId: accountId) else {
            return nil
        }
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    private func rawCredentialBlob(accountId: String) throws -> Data? {
        let stmt = try prepare("SELECT auth_blob FROM credentials WHERE account_id = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }

        try bind(accountId, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        return sqlite3ColumnTextData(stmt, column: 0)
    }

    private func rawUsageSnapshot(accountId: String) throws -> Data? {
        let stmt = try prepare("SELECT snapshot_json FROM usage_snapshots WHERE account_id = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }

        try bind(accountId, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        return sqlite3ColumnTextData(stmt, column: 0)
    }

    private func deleteRowLocked(table: String, accountId: String) throws {
        let stmt = try prepare("DELETE FROM \(table) WHERE account_id = ?;")
        defer { sqlite3_finalize(stmt) }

        try bind(accountId, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw errorFromDB("delete \(table)")
        }
    }

    private func decodeAuthBlob(from data: Data) throws -> AuthBlob {
        do {
            return try decoder.decode(AuthBlob.self, from: data)
        } catch {
            throw AccountDatabaseError.migrationFailed("无法解码 auth_blob")
        }
    }

    private func account(from stmt: OpaquePointer) throws -> Account {
        let id = sqlite3ColumnText(stmt, column: 0)
        let email = sqlite3ColumnText(stmt, column: 1)
        let maskedEmail = sqlite3ColumnText(stmt, column: 2)
        let accountType = sqlite3ColumnOptionalText(stmt, column: 3).flatMap { AccountType(rawValue: $0) }
        let planType = sqlite3ColumnOptionalText(stmt, column: 4).flatMap { PlanType(rawValue: $0) }
        let chatgptAccountId = sqlite3ColumnOptionalText(stmt, column: 5)
        let addedAt = Date(timeIntervalSince1970: sqlite3ColumnDouble(stmt, column: 6))
        let lastUsedAt = sqlite3ColumnIsNull(stmt, column: 7) ? nil : Date(timeIntervalSince1970: sqlite3ColumnDouble(stmt, column: 7))
        let isCurrent = sqlite3ColumnInt(stmt, column: 8) != 0
        let usageError = sqlite3ColumnOptionalText(stmt, column: 9)
        let usageSnapshot: UsageSnapshot?
        if let snapshotData = sqlite3ColumnTextData(stmt, column: 10) {
            usageSnapshot = try decoder.decode(UsageSnapshot.self, from: snapshotData)
        } else {
            usageSnapshot = nil
        }

        return Account(
            id: id,
            email: email,
            maskedEmail: maskedEmail,
            accountType: accountType,
            planType: planType,
            chatgptAccountId: chatgptAccountId,
            addedAt: addedAt,
            lastUsedAt: lastUsedAt,
            usageSnapshot: usageSnapshot,
            usageError: usageError,
            isCurrent: isCurrent
        )
    }

    private func loadLegacyRegistryAccounts(from url: URL) throws -> [LegacyAccount] {
        let data = try Data(contentsOf: url)
        if let wrapped = try? decoder.decode(LegacyRegistryFile.self, from: data) {
            return wrapped.accounts
        }
        return try decoder.decode([LegacyAccount].self, from: data)
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw AccountDatabaseError.executionFailed(message)
        }
    }

    private func writeTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else {
            throw AccountDatabaseError.openFailed("数据库未打开")
        }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let stmt else {
            throw errorFromDB(sql)
        }
        return stmt
    }

    private func bind(_ text: String?, at index: Int32, to stmt: OpaquePointer) throws {
        guard let text else {
            sqlite3_bind_null(stmt, index)
            return
        }
        let result = sqlite3_bind_text(stmt, index, text, -1, sqliteTransientDestructor)
        guard result == SQLITE_OK else {
            throw errorFromDB("bind text")
        }
    }

    private func bind(_ value: Double?, at index: Int32, to stmt: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        let result = sqlite3_bind_double(stmt, index, value)
        guard result == SQLITE_OK else {
            throw errorFromDB("bind double")
        }
    }

    private func bind(_ value: Int?, at index: Int32, to stmt: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        let result = sqlite3_bind_int(stmt, index, Int32(value))
        guard result == SQLITE_OK else {
            throw errorFromDB("bind int")
        }
    }

    private func bindRawAuthBlob(_ blob: AuthBlob, at index: Int32, to stmt: OpaquePointer) throws {
        let data = try encoder.encode(blob)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AccountDatabaseError.executionFailed("无法编码 auth_blob")
        }
        try bind(json, at: index, to: stmt)
    }

    private func bindRawJSON<T: Encodable>(_ value: T, at index: Int32, to stmt: OpaquePointer) throws {
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AccountDatabaseError.executionFailed("无法编码 JSON")
        }
        try bind(json, at: index, to: stmt)
    }

    private func sqlite3ColumnText(_ stmt: OpaquePointer, column: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, column) else {
            return ""
        }
        return String(cString: cString)
    }

    private func sqlite3ColumnOptionalText(_ stmt: OpaquePointer, column: Int32) -> String? {
        guard !sqlite3ColumnIsNull(stmt, column: column) else {
            return nil
        }
        return sqlite3ColumnText(stmt, column: column)
    }

    private func sqlite3ColumnTextData(_ stmt: OpaquePointer, column: Int32) -> Data? {
        guard let cString = sqlite3_column_text(stmt, column) else {
            return nil
        }
        return Data(bytes: cString, count: Int(strlen(cString)))
    }

    private func sqlite3ColumnDouble(_ stmt: OpaquePointer, column: Int32) -> Double {
        sqlite3_column_double(stmt, column)
    }

    private func sqlite3ColumnInt(_ stmt: OpaquePointer, column: Int32) -> Int {
        Int(sqlite3_column_int(stmt, column))
    }

    private func sqlite3ColumnIsNull(_ stmt: OpaquePointer, column: Int32) -> Bool {
        sqlite3_column_type(stmt, column) == SQLITE_NULL
    }

    private func errorFromDB(_ context: String) -> Error {
        if let db {
            let message = String(cString: sqlite3_errmsg(db))
            return AccountDatabaseError.executionFailed("\(context): \(message)")
        }
        return AccountDatabaseError.executionFailed(context)
    }

    private func ensureAppSupportDirectory() throws {
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func decodeStoredAuthBase64(_ storedAuth: String) -> AuthBlob? {
        guard let data = Data(base64Encoded: storedAuth) else {
            return nil
        }
        return try? decoder.decode(AuthBlob.self, from: data)
    }

}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
