## 1. 依赖与基础设施

- [ ] 1.1 `Package.swift` 添加 GRDB.swift 依赖（`from: "7.0.0"`），或 libsqlite3 C API 自封装
- [ ] 1.2 `swift build` 通过

## 2. AccountDatabase 服务

- [ ] 2.1 新建 `CXSwitch/Services/AccountDatabase.swift`
- [ ] 2.2 建表：`accounts`、`credentials`（auth_blob TEXT）、`usage_snapshots`（snapshot_json TEXT）
- [ ] 2.3 开启 `PRAGMA journal_mode = WAL` 和 `PRAGMA foreign_keys = ON`
- [ ] 2.4 实现 `loadAllAccounts`、`saveAccount`、`deleteAccount`、`currentAccount`
- [ ] 2.5 实现 `setCurrentAccount(id:)` — 事务内清旧 is_current + 设新 is_current
- [ ] 2.6 实现 `saveCredential`、`loadCredential`、`deleteCredential`
- [ ] 2.7 实现 `saveUsageSnapshot`、`loadUsageSnapshot`

## 3. 迁移

- [ ] 3.1 实现 `migrateIfNeeded`：DB 不存在 + registry.json 存在 → 读 registry → 写入 DB（accounts + credentials from storedAuth + usage_snapshots）
- [ ] 3.2 迁移 Keychain 凭证（如 authKeychainKey 存在，从 KeychainService 读取写入 DB credentials）
- [ ] 3.3 迁移完成后 registry.json → registry.json.migrated

## 4. Account 模型简化

- [ ] 4.1 移除 `storedAuth: String?`
- [ ] 4.2 移除 `authKeychainKey: String?`
- [ ] 4.3 所有 View 编译通过

## 5. AppState 重构

- [ ] 5.1 新增 `accountDB: AccountDatabase` 属性，init 时创建并 `migrateIfNeeded`
- [ ] 5.2 `loadDashboard`：`accountDB.loadAllAccounts()` 替换 `accountStore.loadRegistry()`；auth.json 不存在时从 DB 恢复
- [ ] 5.3 `switchAccount` 乐观更新：Phase 1 立即更新 UI + showStatus；Phase 2 后台 `accountDB.loadCredential` → `accountDB.setCurrentAccount` → `writeAuthFile` → `restartAndInitialize` → `waitForAccountReady` → `saveUsageSnapshot`；失败回滚
- [ ] 5.4 `importRefreshToken` 两阶段：交换后从 JWT 构造临时账号立即显示；后台事务 `saveAccount` + `saveCredential` + `setCurrentAccount` + `writeAuthFile` → restart → 实时数据
- [ ] 5.5 `removeAccount`：`accountDB.deleteAccount()`（CASCADE 自动清理）
- [ ] 5.6 `refreshSavedAccounts` / `refreshCurrentAccount`：用量更新 `accountDB.saveUsageSnapshot()`
- [ ] 5.7 `persistAccount`：改为 `accountDB.saveAccount()` + `accountDB.saveCredential()`

## 6. 清理旧代码

- [ ] 6.1 移除 `accountCacheByID` 及相关的 `mergeAccountCache`、`syncCurrentAccountFromSavedAccounts`（DB 查询替代）
- [ ] 6.2 移除 `encodeStoredAuth`、`decodeStoredAuth`、`resolveAuthBlob`
- [ ] 6.3 移除 `scheduleRegistryWrite`、`registryDirty`、`persistRegistrySnapshot`（SQLite 事务替代防抖）
- [ ] 6.4 `AccountStore`：移除 `loadRegistry`、`saveRegistry`、`RegistryFile`，保留 `loadPreferences`/`savePreferences` + `readAuthFile`/`writeAuthFile`
- [ ] 6.5 `KeychainService`：迁移完成后可整体删除（或保留供迁移用，标记 deprecated）

## 7. auth.json 恢复

- [ ] 7.1 `loadDashboard` 启动时：auth.json 不存在/损坏 + DB 有 is_current → 从 DB credentials 恢复写入 auth.json
- [ ] 7.2 auth.json 的 `auth_mode` 必须为 `"chatgpt"`（codex app-server 要求）

## 8. waitForAccountReady 优化

- [ ] 8.1 保持指数退避：300ms → 500ms → 1s → 2s → 3s
- [ ] 8.2 成功即返回

## 9. 验证

- [ ] 9.1 `swift build` 通过
- [ ] 9.2 全新安装：无 DB 无 registry → 启动正常，导入 token 后 DB 创建
- [ ] 9.3 从 registry.json 迁移：启动后自动迁移，registry.json → .migrated
- [ ] 9.4 切换账号：点击后 UI 立即更新（<200ms），实时数据后台补齐
- [ ] 9.5 导入 Token：交换后立即显示新账号，后台补齐用量
- [ ] 9.6 删除账号：CASCADE 清理凭证 + 用量
- [ ] 9.7 auth.json 恢复：手动删除 → 重启 → 自动恢复
- [ ] 9.8 连续快速切换：事务保证一致，无凭证错乱
- [ ] 9.9 后台同步失败：UI 回滚到前一个账号 + 显示错误
