## Context

当前首页 FooterActions 是 2 列网格，6 个按钮：添加账户、导入 Token、状态、邮箱脱敏、设置、退出。用户反馈操作太多不直观。

## Goals / Non-Goals

**Goals:**
- 首页干净：只保留 4 个高频按钮
- 设置面板收纳所有低频偏好项
- 新增中英文切换和主题切换

**Non-Goals:**
- 不改变数据模型（Preferences 已有 `language` 字段，新增 `theme` 字段）
- 不改变账户管理逻辑

## Decisions

### 1. 首页 4 个按钮布局

```
┌──────────────────────────────────────┐
│  [+ 添加账户]    [📋 导入 Token]     │
│  [⚙ 设置]       [⏻ 退出]            │
└──────────────────────────────────────┘
```

2×2 网格，每个按钮图标+文字，保持现有 `actionCell` 样式。

### 2. 设置面板（内联切换，非弹窗）

点击"设置"后，首页内容切换为设置面板（和之前的设置逻辑一致，用 `showSettings` 状态控制）：

```
┌──────────────────────────────────────┐
│  ← 返回          设置                │
├──────────────────────────────────────┤
│                                      │
│  邮箱脱敏                    [开关]  │
│                                      │
│  语言                                │
│  ○ 中文  ○ English                   │
│                                      │
│  主题                                │
│  ○ 跟随系统  ○ 亮色  ○ 暗色         │
│                                      │
├──────────────────────────────────────┤
│  OpenAI 状态           →             │
│  打开配置文件夹         →             │
└──────────────────────────────────────┘
```

### 3. Preferences 模型扩展

```swift
struct Preferences: Codable {
    static let defaultLanguage = "zh"

    var language: String           // "zh" | "en"
    var maskEmails: Bool?
    var theme: String?             // 新增: "system" | "light" | "dark"，默认 "system"
    var refreshPolicy: String?
    var dataFolder: String?
}
```

### 4. 主题切换实现

`AppState` 新增 `setTheme(_:)` 方法，通过 `NSApp.appearance` 设置：

```swift
func setTheme(_ theme: String) {
    preferences.theme = theme
    try? accountStore.savePreferences(preferences)
    applyTheme()
}

private func applyTheme() {
    switch preferences.theme {
    case "light":
        NSApp.appearance = NSAppearance(named: .aqua)
    case "dark":
        NSApp.appearance = NSAppearance(named: .darkAqua)
    default:
        NSApp.appearance = nil  // 跟随系统
    }
}
```

启动时也调用 `applyTheme()`。

### 5. 语言切换

已有 `Preferences.language` 和 `Strings.languageProvider`。新增 `setLanguage(_:)` 方法：

```swift
func setLanguage(_ language: String) {
    preferences.language = language
    applyPreferencesSideEffects()  // 更新 Strings.languageProvider
    try? accountStore.savePreferences(preferences)
}
```

切换后 UI 通过 `@Observable` 自动刷新所有 `Strings.xxx` 引用。

### 6. 新增 SettingsView.swift

独立视图文件，接收 `AppState` 环境：

```swift
struct SettingsView: View {
    @Environment(AppState.self) private var state
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: 返回 + 标题
            // Toggle: 邮箱脱敏
            // Picker: 语言 (zh / en)
            // Picker: 主题 (system / light / dark)
            // Divider
            // Button: OpenAI 状态 →
            // Button: 打开配置文件夹 →
        }
    }
}
```

### 7. Strings 新增

```swift
static var language: String { L("语言", en: "Language") }
static var theme: String { L("主题", en: "Theme") }
static var themeSystem: String { L("跟随系统", en: "System") }
static var themeLight: String { L("亮色", en: "Light") }
static var themeDark: String { L("暗色", en: "Dark") }
static var languageChinese: String { "中文" }  // 固定不随语言变
static var languageEnglish: String { "English" }  // 固定不随语言变
static var openaiStatus: String { L("OpenAI 状态", en: "OpenAI Status") }
```

## 文件修改范围

| 文件 | 修改内容 |
|------|----------|
| **新增** `Views/SettingsView.swift` | 设置面板视图 |
| `Views/MenuBarView.swift` | 加 `showSettings` 状态切换；首页/设置面板二选一显示 |
| `Views/FooterActions.swift` | 精简为 4 个按钮：添加账户、导入 Token、设置、退出 |
| `Models/Preferences.swift` | 新增 `theme: String?` 字段 |
| `Models/AppState.swift` | 新增 `setTheme(_:)`、`setLanguage(_:)`、`applyTheme()`；启动时调用 `applyTheme()` |
| `Utilities/Strings.swift` | 新增语言/主题/状态相关字符串 |
