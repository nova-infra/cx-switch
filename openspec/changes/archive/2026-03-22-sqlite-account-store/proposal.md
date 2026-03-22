## Why

当前账号管理存在两大问题：

1. **数据脆弱**：registry.json 单文件存储所有账号元数据+凭证，频繁写入导致污染/损坏，用户被迫重新登录
2. **切换缓慢**：切换账号串行执行 写 auth → 重启 app-server → 轮询就绪 → 落盘，体感 3-7 秒

本次合并 `sqlite-account-store` + `switch-acceleration` 两个方向，彻底重构账号存储和切换流程。

## What Changes

**存储层重构：**
- registry.json → SQLite（accounts / credentials / usage_snapshots 三表）
- 凭证独立存储，单条损坏不影响其他账号
- 事务保证原子性，切换/导入失败自动回滚
- auth.json 降级为 codex CLI 投影文件，可随时从 DB 恢复

**切换/导入加速：**
- 乐观 UI 更新：点击切换后立即从 DB 缓存刷新界面（<200ms）
- 后台异步完成 auth.json 写入、app-server 重启、实时数据拉取
- registry 写入防抖不再需要（SQLite 事务天然合并）
- 导入 Token 两阶段：交换后从 JWT 立即构造账号显示，后台补齐实时数据

**清理：**
- 移除 `storedAuth`、`authKeychainKey` 字段
- 移除 `accountCacheByID` 手动缓存、`encodeStoredAuth`/`decodeStoredAuth`/`resolveAuthBlob`
- 移除 `AccountStore` 的 registry 相关代码
- 移除 registry 写入防抖（`scheduleRegistryWrite`）
