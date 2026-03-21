# CX Switch — SwiftUI Rewrite Specification

## Overview

CX Switch 是一款 macOS 菜单栏（Menu Bar）应用，用于管理和切换多个 OpenAI/ChatGPT 账户。用户可以查看当前账户用量、一键切换已保存的账户、添加新账户、导入 Refresh Token 等。

本次使用 SwiftUI 从零重写，替换原有的 Electrobun (TypeScript/Bun) 实现。

## Target

- **平台**: macOS 14+ (Sonoma)
- **语言**: Swift 6 + SwiftUI
- **架构**: SwiftUI `MenuBarExtra` + `@Observable` 状态管理
- **构建**: Xcode 16+ / Swift Package Manager
- **签名**: Development signing (本地开发)

## 项目结构

```
CXSwitch/
├── CXSwitchApp.swift           # @main 入口，MenuBarExtra 定义
├── Views/
│   ├── MenuBarView.swift        # 菜单栏主视图
│   ├── AccountRow.swift         # 单个账户行（含 ProgressView）
│   ├── UsageBar.swift           # 用量进度条组件
│   ├── LoginFlowView.swift      # 添加账户流程视图
│   └── SettingsView.swift       # 偏好设置视图
├── Models/
│   ├── Account.swift            # 账户数据模型
│   ├── UsageSnapshot.swift      # 用量快照模型
│   ├── Preferences.swift        # 用户偏好模型
│   └── AppState.swift           # 全局应用状态 (@Observable)
├── Services/
│   ├── CodexAppServer.swift     # 与 `codex app-server` 的 JSON-RPC 通信
│   ├── AccountStore.swift       # 账户注册表持久化 (JSON 文件)
│   ├── KeychainService.swift    # macOS Keychain 读写
│   ├── AuthService.swift        # OpenAI OAuth token 交换
│   └── UsageProbe.swift         # 直接探测账户用量 (HTTP)
├── Utilities/
│   ├── JWTDecoder.swift         # JWT payload 解码
│   └── EmailMasker.swift        # 邮箱脱敏
├── Resources/
│   └── Assets.xcassets          # App icon, tray icon
└── Info.plist
```

## 数据模型

### Account

```swift
struct Account: Identifiable, Codable {
    let id: String                          // UUID 或 chatgptAccountId
    var email: String
    var maskedEmail: String
    var planType: PlanType?                 // free|go|plus|pro|team|business|enterprise|edu
    var chatgptAccountId: String?
    var addedAt: Date
    var lastUsedAt: Date?
    var usageSnapshot: UsageSnapshot?
    var usageError: String?
    var isCurrent: Bool = false
}
```

### PlanType

```swift
enum PlanType: String, Codable, CaseIterable {
    case free, go, plus, pro, team, business, enterprise, edu, unknown
}
```

### UsageSnapshot

```swift
struct UsageSnapshot: Codable {
    var limitId: String?
    var planType: PlanType?
    var updatedAt: Date?
    var primary: UsageWindow?
    var secondary: UsageWindow?
    var credits: Credits?
}

struct UsageWindow: Codable {
    var label: String                       // "5 Hours" 或 "Weekly"
    var windowDurationMins: Int
    var usedPercent: Double                  // 0.0 ~ 100.0
    var resetsAt: Date?
}

struct Credits: Codable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}
```

### Preferences

```swift
struct Preferences: Codable {
    var maskEmails: Bool = true
}
```

### AuthBlob

```swift
struct AuthBlob: Codable {
    var authMode: String?
    var lastRefresh: String?
    var tokens: AuthTokens?
    var openaiApiKey: String?
}

struct AuthTokens: Codable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var accountId: String?
}
```

## 核心服务

### 1. CodexAppServer

与 `codex app-server` 子进程通过 stdin/stdout JSON-RPC 通信。

```
启动命令: codex app-server --listen stdio://
```

**请求方法:**
- `initialize` — 握手，传入 clientInfo 和 protocolVersion
- `account/read` — 读取当前活跃账户信息
- `account/rateLimits/read` — 读取当前账户用量
- `account/login/start` — 启动 ChatGPT 登录流程，返回 authUrl
- `account/login/cancel` — 取消登录
- `account/login/completed` — (通知) 登录完成回调

**实现要点:**
- 使用 `Process` 启动子进程
- stdin 写入 JSON-RPC 请求，stdout 逐行读取响应
- 支持请求超时 (默认 20 秒)
- 通知监听 (用于登录完成回调)
- 支持 `restart()` 和 `shutdown()`
- 启动失败重试 3 次，间隔递增

### 2. AccountStore

文件持久化，兼容原有格式。

**文件路径:**
- 注册表: `~/Library/Application Support/com.bigo.cx-switch/registry.json`
- 偏好: `~/Library/Application Support/com.bigo.cx-switch/preferences.json`
- 当前认证: `~/.codex/auth.json`

**registry.json 格式:**
```json
{
  "version": 1,
  "accounts": [...]
}
```

**操作:**
- `loadRegistry() -> [Account]`
- `saveRegistry([Account])`
- `loadPreferences() -> Preferences`
- `savePreferences(Preferences)`
- `readCurrentAuthBlob() -> AuthBlob?`
- `writeCurrentAuthBlob(AuthBlob)`
- 原子写入: 写临时文件再 rename

### 3. KeychainService

使用 macOS Security framework。

```
Service: "com.bigo.cx-switch.account"
Account: 账户 ID
Value: Base64 编码的 AuthBlob JSON
```

**操作:**
- `save(accountId: String, auth: AuthBlob)`
- `load(accountId: String) -> AuthBlob?`
- `delete(accountId: String)`

### 4. AuthService

直接调用 OpenAI OAuth 端点交换 Refresh Token。

```
URL: https://auth.openai.com/oauth/token
Client ID: app_EMoamEEZ73f0CkXaXp7hrann
Grant Type: refresh_token
Scope: openid profile email
```

### 5. UsageProbe

直接调用 ChatGPT API 探测用量（通过响应头获取）。

```
URL: https://chatgpt.com/backend-api/codex/responses
Method: POST (发送最小请求，max_output_tokens=1, store=false)
```

**响应头解析:**
- `x-codex-primary-used-percent`
- `x-codex-primary-reset-after-seconds`
- `x-codex-primary-window-minutes`
- `x-codex-secondary-used-percent`
- `x-codex-secondary-reset-after-seconds`
- `x-codex-secondary-window-minutes`

## UI 设计

### MenuBarExtra (主入口)

```swift
@main
struct CXSwitchApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("CX", systemImage: "arrow.triangle.swap") {
            MenuBarView(state: appState)
        }
        .menuBarExtraStyle(.window)    // 使用窗口样式，支持自定义视图
    }
}
```

> 使用 `.window` 样式而非 `.menu`，这样可以渲染自定义 SwiftUI 视图（ProgressView、按钮等）。

### MenuBarView 布局

```
┌─────────────────────────────────┐
│  ✦ Current Account               │
│  user@email.com                   │
│  Pro Plan                         │
│                                   │
│  5 Hours  ████████░░  80%  1h30m  │
│  Weekly   ██░░░░░░░░  20%  3d     │
│                                   │
│  [Save Current Account]           │ ← 仅当未保存时显示
├─────────────────────────────────┤
│  Switch To                        │
│                                   │
│  ┌─────────────────────────────┐ │
│  │ other@email.com    (plus)   │ │
│  │ ████░░░░░░ 40%             │ │
│  └─────────────────────────────┘ │
│  ┌─────────────────────────────┐ │
│  │ third@email.com    (team)   │ │
│  │ ██████░░░░ 60%             │ │
│  └─────────────────────────────┘ │
├─────────────────────────────────┤
│  [+ Add Account]                  │
│  [↻ Refresh]                      │
├─────────────────────────────────┤
│  ⚠ Error message (if any)        │
├─────────────────────────────────┤
│  Settings…          Status Page   │
│         Quit CX Switch            │
└─────────────────────────────────┘
```

### UsageBar 组件

原生 `ProgressView` + 标签文字：

```swift
struct UsageBar: View {
    let label: String           // "5 Hours"
    let usedPercent: Double     // 0~100
    let resetsAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(resetTimeText).font(.caption2).foregroundStyle(.tertiary)
            }
            ProgressView(value: usedPercent, total: 100)
                .tint(progressColor)
            Text("\(Int(usedPercent))% used").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
```

颜色规则:
- 0-60%: `.green`
- 60-85%: `.orange`
- 85-100%: `.red`

### AccountRow 组件

可点击的账户行，点击触发切换：

```swift
struct AccountRow: View {
    let account: Account
    let maskEmails: Bool
    let onSwitch: () -> Void

    var body: some View {
        Button(action: onSwitch) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayEmail).font(.body)
                    Spacer()
                    if let plan = account.planType {
                        Text(plan.rawValue).font(.caption).padding(.horizontal, 6)
                            .background(.quaternary).clipShape(Capsule())
                    }
                }
                if let usage = account.usageSnapshot?.primary {
                    UsageBar(label: usage.label, usedPercent: usage.usedPercent, resetsAt: usage.resetsAt)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
```

## 应用状态 (AppState)

```swift
@Observable
class AppState {
    var currentAccount: Account?
    var savedAccounts: [Account] = []
    var preferences: Preferences = Preferences()
    var loginFlow: LoginFlowState = LoginFlowState()
    var isRefreshing: Bool = false
    var statusMessage: String?
    var errorMessage: String?
    var noticeMessage: String?

    private let appServer = CodexAppServer()
    private let accountStore = AccountStore()
    private let keychainService = KeychainService()
    private let authService = AuthService()
    private let usageProbe = UsageProbe()
}
```

**核心方法:**
- `loadDashboard()` — 加载当前账户 + 已保存账户 + 偏好
- `refreshCurrentAccount()` — 刷新当前账户信息和用量
- `refreshSavedAccounts(force: Bool)` — 并发刷新已保存账户用量 (并发度 2)
- `saveCurrentAccount()` — 将当前账户保存到注册表 + Keychain
- `switchAccount(to: Account)` — 切换账户 (写 auth.json → 重启 app-server)
- `removeAccount(Account)` — 删除已保存账户
- `startAddAccount()` — 启动 ChatGPT OAuth 登录流程
- `cancelAddAccount()` — 取消登录
- `importRefreshToken(String)` — 导入 Refresh Token
- `setMaskEmails(Bool)` — 切换邮箱脱敏
- `openStatusPage()` — 打开 https://status.openai.com/
- `openSettings()` — 打开数据文件夹
- `quit()` — 退出应用

## 关键行为

### 启动流程
1. 初始化 AppState
2. 启动 `codex app-server` 子进程并 `initialize`
3. 调用 `account/read` 获取当前账户
4. 调用 `account/rateLimits/read` 获取当前用量
5. 加载已保存账户注册表
6. 后台刷新过期的已保存账户用量 (>60 秒视为过期)

### 账户切换流程
1. 从 Keychain 读取目标账户的 AuthBlob
2. 写入 `~/.codex/auth.json`
3. 重启 `codex app-server`
4. 刷新 UI

### 添加账户流程
1. 调用 `account/login/start` → 获取 authUrl
2. 用 `NSWorkspace.shared.open(url)` 打开浏览器
3. 等待 `account/login/completed` 通知 (超时 10 分钟)
4. 成功后读取新账户信息，保存到注册表 + Keychain

### 导入 Refresh Token 流程
1. 清理输入 (去除引号、空白)
2. 调用 OpenAI OAuth 端点交换 token
3. 写入 `~/.codex/auth.json`
4. 重启 `codex app-server`
5. 读取账户信息，保存到注册表 + Keychain

### 用量探测流程
1. 用已保存的 access_token 发送最小化 Codex 请求
2. 解析响应头中的 `x-codex-*` 用量信息
3. 识别 5 小时窗口和周窗口
4. 超时 15 秒

## 应用配置

```
Bundle ID: com.bigo.cx-switch
App Name: CX Switch
Keychain Service: com.bigo.cx-switch.account
LSUIElement: true (无 Dock 图标)
```

## 兼容性要求

- 数据格式必须与 Electrobun 版本兼容 (registry.json, auth.json, Keychain)
- 用户从 Electrobun 版本切换到 SwiftUI 版本后，已保存的账户数据不丢失
- `codex app-server` 的 JSON-RPC 协议保持不变

## 非目标 (不需要实现)

- 自动更新
- 多语言/国际化
- 单元测试 (首版)
- Sparkle 集成
- 登录流程的内嵌 WebView (使用系统浏览器)
