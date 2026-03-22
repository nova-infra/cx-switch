## Context

当前存储架构：
- `~/Library/Application Support/com.novainfra.cx-switch/registry.json` — 所有账号元数据 + storedAuth (Base64 凭证)
- `~/.codex/auth.json` — 当前激活账号凭证（codex CLI 共享）
- `~/Library/Application Support/com.novainfra.cx-switch/preferences.json` — 用户偏好

问题：registry.json 既存元数据又存凭证，频繁读写，损坏后全部账号数据丢失。

## Goals / Non-Goals

**Goals:**
- 账号数据用 SQLite 存储，单条记录损坏不影响其他账号
- 凭证和元数据分表存储
- 切换/导入操作在事务内完成，失败自动回滚
- 从 registry.json 自动迁移，用户无感
- `~/.codex/auth.json` 可随时从 DB 恢复

**Non-Goals:**
- 不改 preferences.json（简单键值文件，无并发问题）
- 不改 codex app-server 通信协议
- 不引入 ORM 框架（直接用 Swift SQLite API）

## Decisions

### 1. 使用 Swift 内置 SQLite（libsqlite3）

macOS 自带 libsqlite3，无需额外依赖。通过 `import SQLite3` 直接使用 C API，或用轻量包装。

推荐方案：用 **GRDB.swift**（Swift Package）或直接封装 C API。考虑到项目已用 Swift Package Manager，GRDB 是最成熟的选择：

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
]
```

如果不想加依赖，也可直接用 `import SQLite3` 封装（~100 行），但 GRDB 提供了类型安全、迁移、事务等开箱即用。

### 2. 数据库 Schema

```sql
-- 账号元数据
CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    masked_email TEXT NOT NULL,
    account_type TEXT,
    plan_type TEXT,
    chatgpt_account_id TEXT,
    added_at TEXT NOT NULL,         -- ISO8601
    last_used_at TEXT,              -- ISO8601
    is_current INTEGER DEFAULT 0,
    usage_error TEXT
);

-- 凭证（独立表，一对一关系）
CREATE TABLE credentials (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    auth_blob TEXT NOT NULL,        -- JSON 字符串（AuthBlob 序列化）
    updated_at TEXT NOT NULL        -- ISO8601
);

-- 用量快照（独立表，可独立更新不影响账号数据）
CREATE TABLE usage_snapshots (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    snapshot_json TEXT NOT NULL,    -- JSON 字符串（UsageSnapshot 序列化）
    updated_at TEXT NOT NULL        -- ISO8601
);
```

分三张表的好处：
- 刷新用量只写 `usage_snapshots`，不碰 `accounts` 和 `credentials`
- 凭证单独存储，即使 `accounts` 行异常也能恢复凭证
- CASCADE 删除：删账号自动清理凭证和快照

### 3. DB 文件位置

```
~/Library/Application Support/com.novainfra.cx-switch/cx-switch.db
```

开启 WAL 模式（并发读写性能更好）：
```sql
PRAGMA journal_mode = WAL;
```

### 4. AccountDatabase 服务

替换当前 `AccountStore` 的 registry 部分（保留 preferences.json 和 auth.json 读写）：

```swift
final class AccountDatabase {
    private let db: DatabaseQueue  // GRDB

    init(path: String) throws { ... }

    // 账号 CRUD
    func loadAllAccounts() throws -> [Account]
    func saveAccount(_ account: Account) throws           // INSERT OR REPLACE
    func deleteAccount(id: String) throws
    func setCurrentAccount(id: String) throws             // 事务：清除旧 is_current + 设置新
    func currentAccount() throws -> Account?

    // 凭证
    func saveCredential(accountId: String, authBlob: AuthBlob) throws
    func loadCredential(accountId: String) throws -> AuthBlob?
    func deleteCredential(accountId: String) throws

    // 用量
    func saveUsageSnapshot(accountId: String, snapshot: UsageSnapshot) throws
    func loadUsageSnapshot(accountId: String) throws -> UsageSnapshot?

    // 迁移
    func migrateFromRegistryJSON(_ registryPath: String, credentialResolver: (Account) -> AuthBlob?) throws
}
```

### 5. 切换账号流程优化（事务保证）

```swift
func switchAccount(to account: Account) async {
    // Phase 1: 乐观更新 UI（不变）
    activateAccountOptimistically(account)

    // Phase 2: 后台事务
    Task {
        do {
            // 1. 从 DB 读取目标账号凭证
            guard let authBlob = try accountDB.loadCredential(accountId: account.id) else {
                throw CXError.missingCredential
            }

            // 2. 事务内切换 is_current
            try accountDB.setCurrentAccount(id: account.id)

            // 3. 写 auth.json（codex CLI 共享文件）
            try accountStore.writeAuthFile(authBlob)

            // 4. 重启 app-server + 拉取实时数据
            try await appServer.restartAndInitialize()
            if let live = await waitForAccountReady(authBlob: authBlob) {
                try accountDB.saveUsageSnapshot(accountId: live.id, snapshot: live.usageSnapshot)
                await MainActor.run { mergeAccountCache(live, updateCurrentAccount: true) }
            }
        } catch {
            // 回滚 UI
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
```

关键改进：凭证从 DB 读取（不再依赖 storedAuth 字段），`setCurrentAccount` 在事务内原子切换。

### 6. 导入 Token 流程优化

```swift
func importRefreshToken(_ rawToken: String) async {
    // ... token 交换 ...

    // 事务：保存账号 + 凭证 + 设置为当前
    try accountDB.saveAccount(newAccount)
    try accountDB.saveCredential(accountId: newAccount.id, authBlob: authBlob)
    try accountDB.setCurrentAccount(id: newAccount.id)

    // 写 auth.json
    try accountStore.writeAuthFile(authBlob)
}
```

一个事务内完成所有写入，中途失败全部回滚，不会出现"账号存了但凭证没存"的半损坏状态。

### 7. 自动迁移 registry.json

首次启动时检测：
- 如果 `cx-switch.db` 不存在但 `registry.json` 存在 → 执行迁移
- 迁移完成后将 `registry.json` 重命名为 `registry.json.migrated`（保留备份）

```swift
func migrateIfNeeded() throws {
    let dbExists = FileManager.default.fileExists(atPath: dbPath)
    let registryExists = FileManager.default.fileExists(atPath: registryPath)

    if !dbExists && registryExists {
        let accounts = try loadRegistryJSON(registryPath)
        for account in accounts {
            try accountDB.saveAccount(account)
            if let storedAuth = account.storedAuth,
               let authBlob = decodeStoredAuth(storedAuth) {
                try accountDB.saveCredential(accountId: account.id, authBlob: authBlob)
            }
            if let snapshot = account.usageSnapshot {
                try accountDB.saveUsageSnapshot(accountId: account.id, snapshot: snapshot)
            }
        }
        try FileManager.default.moveItem(atPath: registryPath, toPath: registryPath + ".migrated")
    }
}
```

### 8. Account 模型简化

迁移后 `storedAuth` 和 `authKeychainKey` 字段不再需要：

```swift
struct Account: Identifiable, Codable {
    let id: String
    var email: String
    var maskedEmail: String
    var accountType: AccountType?
    var planType: PlanType?
    var chatgptAccountId: String?
    var addedAt: Date
    var lastUsedAt: Date?
    var usageSnapshot: UsageSnapshot?     // 运行时从 DB join 加载
    var usageError: String?
    var isCurrent: Bool = false
    // 删除: storedAuth, authKeychainKey
}
```

凭证从 `credentials` 表按需加载，不再混在 Account 模型里。

## 文件修改范围

| 文件 | 改动 |
|------|------|
| **新增** `Services/AccountDatabase.swift` | SQLite 数据库服务（~200 行） |
| `Package.swift` | 添加 GRDB.swift 依赖（或用 libsqlite3 自封装） |
| `Services/AccountStore.swift` | 移除 registry.json 读写，保留 preferences.json 和 auth.json |
| `Models/Account.swift` | 移除 `storedAuth`、`authKeychainKey` 字段 |
| `Models/AppState.swift` | `accountStore` registry 调用 → `accountDB` 调用；移除 `encodeStoredAuth`/`decodeStoredAuth`/`resolveAuthBlob`，改为 `accountDB.loadCredential` |
| `Utilities/GlassCompat.swift` | 不改 |
| Views | 不改（Account 模型接口不变） |

## Risks / Trade-offs

- [新增 GRDB 依赖] → 包体增大 ~1MB。Mitigation: GRDB 是纯 Swift，无 ObjC 桥接。或者用 libsqlite3 C API 自封装免依赖。
- [迁移失败] → 保留 registry.json.migrated 备份，用户可手动恢复。
- [DB 文件损坏] → SQLite WAL 模式 + 原子事务极大降低概率。极端情况下 DB 损坏只影响本地缓存，用户重新导入 token 即可恢复。
