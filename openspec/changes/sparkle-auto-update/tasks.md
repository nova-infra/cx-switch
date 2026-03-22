## 1. Sparkle 依赖

- [x] 1.1 `Package.swift` 添加 `Sparkle` 2.6+ SPM 依赖
- [x] 1.2 CXSwitch target 添加 `.product(name: "Sparkle", package: "Sparkle")` dependency
- [x] 1.3 `swift build` 确认编译通过

## 2. EdDSA 密钥生成

- [x] 2.1 运行 `.build/artifacts/sparkle/Sparkle/bin/generate_keys` 生成密钥对
- [x] 2.2 私钥确认已存入 macOS Keychain
- [x] 2.3 记录公钥字符串

## 3. Info.plist 配置

- [x] 3.1 添加 `SUFeedURL` = `https://nova-infra.github.io/cx-switch/appcast.xml`
- [x] 3.2 添加 `SUPublicEDKey` = 步骤 2.3 的公钥

## 4. UpdaterService

- [x] 4.1 新增 `CXSwitch/Services/UpdaterService.swift`
- [x] 4.2 使用 `SPUStandardUpdaterController(startingUpdater: true, ...)`
- [x] 4.3 暴露 `checkForUpdates()` 和 `canCheckForUpdates`

## 5. App 入口集成

- [x] 5.1 `CXSwitchApp.swift` 导入 Sparkle
- [x] 5.2 创建 `UpdaterService` 实例
- [x] 5.3 通过 `.environmentObject(updaterService)` 注入

## 6. SettingsView 替换

- [x] 6.1 添加 `@EnvironmentObject private var updaterService: UpdaterService`
- [x] 6.2 替换 `versionSection`：删除 `updateStatusView`、`openLatestRelease()`
- [x] 6.3 "检查更新"按钮调用 `updaterService.checkForUpdates()`

## 7. AppState 清理

- [x] 7.1 删除 `updateStatus` 属性
- [x] 7.2 删除 `enum UpdateStatus`
- [x] 7.3 删除 `func checkForUpdates() async`
- [x] 7.4 保留 `static let appVersion`

## 8. Strings 清理

- [x] 8.1 删除 `upToDate`、`newVersionAvailable`、`checkingUpdates`、`updateFailed`（Sparkle 自带 UI）
- [x] 8.2 保留 `version`、`checkForUpdates`

## 9. Appcast

- [x] 9.1 新增 `docs/appcast.xml` 空壳文件
- [ ] 9.2 推送后确认 GitHub Pages 可访问 `https://nova-infra.github.io/cx-switch/appcast.xml`

## 10. 发版脚本

- [x] 10.1 新增 `scripts/release.sh`，自动化以下步骤：
  - `swift build -c release`
  - 打包 .app bundle（含 Info.plist、AppIcon.icns）
  - 签名 `codesign --force --deep --sign -`
  - 创建 DMG
  - `sign_update` 签名 DMG
  - 输出 appcast `<item>` XML 片段
- [ ] 10.2 手动测试发版流程

## 11. 验证

- [x] 11.1 `swift build` 编译通过
- [ ] 11.2 设置页显示版本号 + "检查更新"按钮
- [ ] 11.3 点击"检查更新"弹出 Sparkle 标准窗口
- [ ] 11.4 appcast 有新版本时，Sparkle 提示下载更新
- [ ] 11.5 更新流程完整：下载 → 替换 → 重启
