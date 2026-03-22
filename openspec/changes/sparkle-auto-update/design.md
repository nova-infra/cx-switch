## Context

CX Switch 是 macOS 菜单栏 app，通过 GitHub Releases 分发。当前 SettingsView 有手动检查更新按钮，查询 GitHub API 对比版本号，有新版时跳转浏览器下载。用户需手动替换 .app，体验差。

## Goals / Non-Goals

**Goals:**
- 用户点"检查更新"后，Sparkle 自动下载 → 替换 → 重启
- 后台定期自动检查（默认 1 小时）
- EdDSA 签名验证，确保更新包完整性
- appcast.xml 托管在 GitHub Pages（零成本）
- 发版流程可脚本化

**Non-Goals:**
- 不做 Apple 公证（notarization）
- 不做 delta 更新（初期不需要）
- 不做自定义更新 UI（用 Sparkle 自带的标准窗口）

## Decisions

### 1. Sparkle 集成方式

使用 `SPUStandardUpdaterController`（不是底层 `SPUUpdater`）。它自带完整 UI（更新提示窗口、下载进度、重启按钮），不需要自己画。对 MenuBarExtra app 无冲突，Sparkle 会创建独立窗口。

### 2. Package.swift 添加依赖

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CXSwitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CXSwitch", targets: ["CXSwitch"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "CXSwitch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "CXSwitch",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
```

### 3. 新增 UpdaterService.swift

```swift
import Foundation
import Sparkle

final class UpdaterService: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

### 4. CXSwitchApp.swift 改动

```swift
import SwiftUI
import Sparkle

@main
struct CXSwitchApp: App {
    @State private var state = AppState()
    private let updaterService = UpdaterService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
                .environmentObject(updaterService)
        } label: {
            Label("CX") { Image(systemName: "bolt.circle").renderingMode(.template) }
        }
        .menuBarExtraStyle(.window)
    }
}
```

### 5. SettingsView 更新 UI 简化

删除 `updateStatusView`、`openLatestRelease()`、`UpdateStatus` 相关逻辑。替换为：

```swift
@EnvironmentObject private var updaterService: UpdaterService

private var versionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("\(Strings.version) \(AppState.appVersion)")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button(action: { updaterService.checkForUpdates() }) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body).foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                Text(Strings.checkForUpdates).font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}
```

### 6. AppState 清理

删除以下代码（约 40 行）：
- `updateStatus` 属性
- `enum UpdateStatus`
- `func checkForUpdates() async`

保留 `static let appVersion`。

### 7. Info.plist 添加 Sparkle 配置

在 `CXSwitch/Resources/Info.plist` 的 `<dict>` 内添加：

```xml
<key>SUFeedURL</key>
<string>https://nova-infra.github.io/cx-switch/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>生成的公钥粘贴到这里</string>
```

### 8. 生成 EdDSA 密钥

```bash
# Sparkle 构建后密钥工具在：
.build/artifacts/sparkle/Sparkle/bin/generate_keys
# 运行后：
# - 私钥自动存入 macOS Keychain
# - 输出公钥字符串 → 粘贴到 Info.plist 的 SUPublicEDKey
```

### 9. appcast.xml（托管在 docs/）

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>CX Switch</title>
    <link>https://nova-infra.github.io/cx-switch/appcast.xml</link>
    <description>CX Switch Updates</description>
    <language>en</language>
    <!-- 每次发版添加一个 item -->
  </channel>
</rss>
```

### 10. 发版流程

```bash
# 1. 构建
swift build -c release

# 2. 打包 .app + .dmg（同现有流程）

# 3. 签名 DMG
.build/artifacts/sparkle/Sparkle/bin/sign_update CXSwitch.dmg
# 输出 edSignature 和 length

# 4. 更新 docs/appcast.xml，添加 <item>：
#    <enclosure url="https://github.com/nova-infra/cx-switch/releases/download/vX.Y.Z/CXSwitch.dmg"
#               sparkle:edSignature="签名" length="字节数" type="application/octet-stream" />

# 5. git commit + push（自动部署 GitHub Pages）
# 6. gh release create vX.Y.Z ...
```

## 文件修改范围

| 文件 | 改动 |
|------|------|
| `Package.swift` | 添加 Sparkle 依赖 |
| **新增** `CXSwitch/Services/UpdaterService.swift` | ~20 行 |
| **新增** `docs/appcast.xml` | ~10 行 |
| `CXSwitch/CXSwitchApp.swift` | 导入 Sparkle，注入 UpdaterService |
| `CXSwitch/Views/SettingsView.swift` | 替换更新 UI，删除旧逻辑 |
| `CXSwitch/Models/AppState.swift` | 删除 UpdateStatus / checkForUpdates |
| `CXSwitch/Resources/Info.plist` | 添加 SUFeedURL + SUPublicEDKey |
| `CXSwitch/Utilities/Strings.swift` | 可删除 checkingUpdates/upToDate 等（Sparkle 自带 UI） |
