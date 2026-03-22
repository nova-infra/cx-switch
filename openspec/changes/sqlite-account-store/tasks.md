## 1. 依赖与基础设施

- [ ] 1.1 `Package.swift` 添加 GRDB.swift 依赖（`from: "7.0.0"`），或选择 libsqlite3 C API 自封装（无外部依赖）
- [ ] 1.2 确认 `swift build` 通过

## 2. 数据库 Schema 与服务

- [ ] 2.1 新建 `CXSwitch/Services/AccountDatabase.swift`
- [ ] 2.2 创建三张表：`accounts`（元数据）、`credentials`（凭证）、`usage_snapshots`（用量）
- [ ] 2.3 开启 WAL 模式（`PRAGMA journal_mode = WAL`）
- [ ] 2.4 实现账号 CRUD：`loadAllAccounts`、`saveAccount`、`deleteAccount`、`setCurrentAccount`、`currentAccount`
- [ ] 2.5 实现凭证 CRUD：`saveCredential`、`loadCredential`、`deleteCredential`
- [ ] 2.6 实现用量 CRUD：`saveUsageSnapshot`、`loadUsageSnapshot`
- [ ] 2.7 `setCurrentAccount` 用事务保证原子性：清除旧 `is_current` → 设置新 `is_current`

## 3. 迁移逻辑

- [ ] 3.1 实现 `migrateFromRegistryJSON`：读取 registry.json → 逐条写入 DB（accounts + credentials + usage_snapshots）
- [ ] 3.2 `migrateIfNeeded`：DB 不存在 + registry.json 存在时触发迁移
- [ ] 3.3 迁移完成后 registry.json 重命名为 `.migrated` 备份
- [ ] 3.4 也迁移 `authKeychainKey` 对应的 Keychain 凭证（如有）

## 4. Account 模型简化

- [ ] 4.1 移除 `storedAuth: String?` 字段
- [ ] 4.2 移除 `authKeychainKey: String?` 字段
- [ ] 4.3 确认所有 View 编译通过（这两个字段不在 View 中使用）

## 5. AppState 改造

- [ ] 5.1 新增 `accountDB: AccountDatabase` 属性，init 时初始化并调用 `migrateIfNeeded`
- [ ] 5.2 `loadDashboard`：从 `accountDB.loadAllAccounts()` 加载（替换 `accountStore.loadRegistry()`）
- [ ] 5.3 `persistAccount`：改为 `accountDB.saveAccount()` + `accountDB.saveCredential()`（从 auth.json 读取凭证写入 DB）
- [ ] 5.4 `switchAccount`：从 `accountDB.loadCredential()` 获取 auth（替换 `resolveAuthBlob`）；用 `accountDB.setCurrentAccount()` 原子切换
- [ ] 5.5 `importRefreshToken`：事务内保存 account + credential + setCurrentAccount
- [ ] 5.6 `removeAccount`：`accountDB.deleteAccount()`（CASCADE 自动清理 credentials + usage_snapshots）
- [ ] 5.7 `refreshSavedAccounts` / `refreshCurrentAccount`：用量更新写入 `accountDB.saveUsageSnapshot()`
- [ ] 5.8 移除 `encodeStoredAuth`、`decodeStoredAuth`、`resolveAuthBlob` 方法
- [ ] 5.9 移除 `accountCacheByID` 手动缓存（DB 查询足够快，或保留为内存缓存但从 DB 填充）

## 6. AccountStore 精简

- [ ] 6.1 移除 `loadRegistry` / `saveRegistry` / `RegistryFile`（不再需要）
- [ ] 6.2 保留 `loadPreferences` / `savePreferences`（preferences.json 不迁移）
- [ ] 6.3 保留 `readAuthFile` / `writeAuthFile`（`~/.codex/auth.json` 仍需要）

## 7. auth.json 恢复能力

- [ ] 7.1 `loadDashboard` 启动时：如果 auth.json 不存在或损坏，但 DB 有 `is_current` 账号 → 从 DB credentials 恢复写入 auth.json
- [ ] 7.2 确保 codex app-server 能正常读取恢复后的 auth.json

## 8. 验证

- [ ] 8.1 `swift build` 通过
- [ ] 8.2 全新安装：无 registry.json、无 DB → 正常启动，导入 token 后 DB 创建
- [ ] 8.3 从 registry.json 迁移：已有 registry.json → 启动后自动迁移到 DB，registry.json 变为 .migrated
- [ ] 8.4 切换账号：凭证从 DB 读取，auth.json 正确写入，app-server 正常响应
- [ ] 8.5 导入 Token：事务内保存，中途模拟失败不留脏数据
- [ ] 8.6 删除账号：CASCADE 清理 credentials + usage_snapshots
- [ ] 8.7 auth.json 恢复：手动删除 auth.json → 重启 app → 自动从 DB 恢复
- [ ] 8.8 连续快速切换：事务保证数据一致，不出现凭证错乱
