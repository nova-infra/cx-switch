## Why

当前使用 registry.json 单文件管理所有账号，存在以下问题：

1. **数据污染**：多次快速写入（切换、刷新、persist）竞争同一个 JSON 文件，部分写入导致数据损坏
2. **凭证丢失**：auth 信息以 Base64 存在 registry.json 的 `storedAuth` 字段里，文件损坏则所有账号凭证全丢，用户被迫重新登录
3. **单点故障**：`~/.codex/auth.json` 是当前账号唯一凭证来源，切换时覆盖写入，中途出错就丢失前一个账号

## What Changes

- 用 SQLite 替换 registry.json 作为账号存储
- 每个账号的 auth 凭证独立存在 DB 行里，互不影响
- `~/.codex/auth.json` 降级为"当前激活账号的投影"——只在切换时写入，随时可从 DB 恢复
- 首次启动自动迁移 registry.json 到 SQLite
- preferences.json 保留（简单键值，不值得迁移）
