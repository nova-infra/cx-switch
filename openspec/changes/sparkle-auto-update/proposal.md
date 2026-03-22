## Why

当前"检查更新"功能只是查 GitHub API 然后跳浏览器下载，用户需要手动替换 .app。Sparkle 框架可以实现真正的热更新：自动检查 → 下载 → 替换 → 重启，一键完成。

## What Changes

- 集成 Sparkle 2.x（SPM 依赖）
- 生成 EdDSA 签名密钥对
- 用 `SPUStandardUpdaterController` 替换手写的更新检查逻辑
- 在 GitHub Pages 托管 `appcast.xml` 更新源
- 每次发版用 `sign_update` 签名 DMG 并更新 appcast

## Impact

- 新增 1 个文件 `UpdaterService.swift`（~20 行）
- 新增 1 个文件 `docs/appcast.xml`
- 删除 AppState 中的 `UpdateStatus` / `checkForUpdates()`（~40 行）
- 简化 SettingsView 更新 UI（~40 行 → ~25 行）
- 新增 SPM 依赖：Sparkle 2.6+
