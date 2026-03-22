## Context

合并两个 change 的目标：
- `sqlite-account-store`：registry.json → SQLite，解决数据污染
- `switch-acceleration`：乐观 UI + 后台同步，解决切换慢

当前代码已完成 switch-acceleration 的大部分实现（乐观更新、waitForAccountReady 退避、状态消息），但仍依赖 registry.json + storedAuth + accountCacheByID 手动缓存。本次用 SQLite 替换底层后，切换加速的实现会更简洁。

## Goals / Non-Goals

**Goals:**
- SQLite 存储，事务保证原子性
- 切换/导入体感 <200ms（乐观 UI）
- auth.json 可从 DB 恢复
- 从 registry.json 自动迁移
- 代码量净减少（移除手动缓存、防抖、序列化）

**Non-Goals:**
- 不改 preferences.json
- 不改 codex app-server 协议
- 不改 View 层接口

## Decisions

### 1. SQLite Schema

```sql
CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    masked_email TEXT NOT NULL,
    account_type TEXT,
    plan_type TEXT,
    chatgpt_account_id TEXT,
    added_at TEXT NOT NULL,
    last_used_at TEXT,
    is_current INTEGER DEFAULT 0,
    usage_error TEXT
);

CREATE TABLE credentials (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    auth_blob TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE usage_snapshots (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    snapshot_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
```

DB 路径：`~/Library/Application Support/com.novainfra.cx-switch/cx-switch.db`

### 2. AccountDatabase 服务

```swift
final class AccountDatabase {
    // 账号
    func loadAllAccounts() throws -> [Account]
    func saveAccount(_ account: Account) throws
    func deleteAccount(id: String) throws
    func setCurrentAccount(id: String) throws      // 事务：清旧 + 设新
    func currentAccount() throws -> Account?

    // 凭证
    func saveCredential(accountId: String, authBlob: AuthBlob) throws
    func loadCredential(accountId: String) throws -> AuthBlob?

    // 用量
    func saveUsageSnapshot(accountId: String, snapshot: UsageSnapshot) throws

    // 迁移
    func migrateIfNeeded(registryPath: String, keychainService: KeychainStoring?) throws
}
```

使用 GRDB.swift（或 libsqlite3 C API 自封装）。

### 3. 切换账号：乐观 UI + DB 事务

```swift
func switchAccount(to account: Account) async {
    // Phase 1: 立即（@MainActor, <50ms）
    let previous = currentAccount
    currentAccount = applyMasking(to: account)
    markCurrentAccount(account)
    showStatus("已切换到 \(account.email)")

    // Phase 2: 后台
    Task {
        do {
            guard let authBlob = try accountDB.loadCredential(accountId: account.id) else {
                throw CXError.missingCredential
            }
            try accountDB.setCurrentAccount(id: account.id)   // 事务
            try accountStore.writeAuthFile(authBlob)           // codex CLI 投影
            try await appServer.restartAndInitialize()

            if let live = await waitForAccountReady(authBlob: authBlob) {
                try? accountDB.saveUsageSnapshot(accountId: live.id, snapshot: live.usageSnapshot)
                await MainActor.run { mergeAccountCache(live, updateCurrentAccount: true) }
            }
        } catch {
            await MainActor.run {
                currentAccount = previous   // 回滚
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

### 4. 导入 Token：JWT 即时显示 + DB 事务

```swift
func importRefreshToken(_ rawToken: String) async {
    // ... token 交换 ...
    let claims = extractClaimsFromIdToken(tokens.idToken)

    // 立即构造临时账号显示
    let tempAccount = Account(id: claims.accountId, email: claims.email, ...)
    currentAccount = tempAccount
    showStatus("已导入 \(claims.email)")

    // 后台事务
    Task {
        try accountDB.saveAccount(tempAccount)
        try accountDB.saveCredential(accountId: tempAccount.id, authBlob: authBlob)
        try accountDB.setCurrentAccount(id: tempAccount.id)
        try accountStore.writeAuthFile(authBlob)
        // ... restart + 实时数据 ...
    }
}
```

### 5. auth.json 恢复

启动时如果 auth.json 不存在/损坏，但 DB 有 is_current 账号：
```swift
if accountStore.readAuthFile() == nil,
   let current = try accountDB.currentAccount(),
   let cred = try accountDB.loadCredential(accountId: current.id) {
    try accountStore.writeAuthFile(cred)
}
```

### 6. 自动迁移

首次启动检测 registry.json → 逐条迁移到 DB → 重命名为 `.migrated`。

### 7. 可移除的代码

| 移除内容 | 原因 |
|----------|------|
| `Account.storedAuth` | 凭证存 DB credentials 表 |
| `Account.authKeychainKey` | 不再用 Keychain |
| `accountCacheByID: [String: Account]` | DB 查询替代 |
| `encodeStoredAuth` / `decodeStoredAuth` | 不再需要 |
| `resolveAuthBlob` | 改为 `accountDB.loadCredential` |
| `scheduleRegistryWrite` / `registryDirty` | SQLite 事务替代防抖 |
| `persistRegistrySnapshot` | 改为 DB 写入 |
| `AccountStore.loadRegistry` / `saveRegistry` | DB 替代 |
| `KeychainService` | 可整体移除（凭证存 DB） |

## 文件修改范围

| 文件 | 改动 |
|------|------|
| **新增** `Services/AccountDatabase.swift` | ~200 行 |
| `Package.swift` | 添加 GRDB 依赖 |
| `Models/Account.swift` | 移除 `storedAuth`、`authKeychainKey` |
| `Models/AppState.swift` | 重构核心：DB 替代 registry，简化切换/导入 |
| `Services/AccountStore.swift` | 移除 registry 代码，保留 preferences + auth.json |
| `Services/KeychainService.swift` | 可删除（迁移时读一次后不再使用） |
| Views | **不改**（Account 对外接口不变） |
