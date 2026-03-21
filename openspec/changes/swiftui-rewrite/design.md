## Context

CX Switch 是 macOS 菜单栏应用，用于管理和切换多个 OpenAI/ChatGPT 账户。原版基于 Electrobun (TypeScript/Bun/React)，本次使用 Swift 6 + SwiftUI 完全重写。

核心约束：
- 必须与原版数据格式兼容（registry.json、auth.json、Keychain）
- 必须继续通过 `codex app-server` JSON-RPC 获取账户和用量信息
- 必须是纯菜单栏应用（无 Dock 图标）
- 目标平台 macOS 14+ (Sonoma)

## Goals / Non-Goals

**Goals:**

- 使用 SwiftUI `MenuBarExtra(.window)` 渲染自定义面板，支持原生 ProgressView 进度条
- 保持全部账户管理功能（查看、切换、添加、删除、保存、导入 Token）
- 保持用量显示功能（5 小时窗口 + 周窗口，进度条 + 重置倒计时）
- 数据格式完全兼容，用户无感切换
- `@Observable` 驱动 UI 状态，响应式更新

**Non-Goals:**

- 自动更新 / Sparkle 集成
- 多语言/国际化
- 单元测试（首版）
- 内嵌 WebView 登录（使用系统浏览器）
- 沙盒化 / Mac App Store 发布

## Decisions

### 1. 使用 `MenuBarExtra(.window)` 而非 `.menu` 样式

- `.window` 样式允许渲染完整 SwiftUI 视图，包括 ProgressView、自定义布局、交互按钮。
- `.menu` 样式只能渲染 `Button`/`Divider`/`Toggle`，无法放置进度条。
- 备选方案：用 NSPopover 手动管理弹出面板；更复杂，且 MenuBarExtra 已经提供了所需能力。

### 2. `@Observable` + 单一 AppState 驱动

- 使用 Swift 5.9+ 的 `@Observable` 宏替代 ObservableObject/Published。
- 单一 `AppState` 类持有所有状态，通过方法暴露操作。
- 备选方案：多个独立 ViewModel；对于此应用规模过度拆分。

### 3. `Process` API 管理子进程

- 使用 Foundation `Process` 启动 `codex app-server --listen stdio://`。
- stdin 写入 JSON-RPC 请求，stdout 逐行读取响应。
- 支持启动重试（3 次，间隔递增）、超时、graceful shutdown。
- 备选方案：通过 TCP/HTTP 通信；app-server 原生支持 stdio，保持一致。

### 4. Security framework 直接访问 Keychain

- 使用 `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete` 替换 shell 调用 `security` 命令。
- Service: `com.bigo.cx-switch.account`，Account: 账户 ID，Value: Base64(AuthBlob JSON)。
- 格式与原版完全兼容。

### 5. 保持原有文件路径和格式

- 注册表: `~/Library/Application Support/com.bigo.cx-switch/registry.json`
- 偏好: `~/Library/Application Support/com.bigo.cx-switch/preferences.json`
- 当前认证: `~/.codex/auth.json`
- 写入策略：原子写入（写临时文件 → rename）

## 项目结构

```
CXSwitch/
├── CXSwitchApp.swift              # @main，MenuBarExtra 定义
├── Views/
│   ├── MenuBarView.swift           # 菜单栏主面板
│   ├── CurrentAccountSection.swift # 当前账户区块
│   ├── SavedAccountRow.swift       # 已保存账户行
│   ├── UsageBar.swift              # 用量进度条组件
│   ├── LoginFlowSheet.swift        # 添加账户流程
│   └── FooterActions.swift         # 底部操作栏
├── Models/
│   ├── Account.swift               # 账户模型
│   ├── UsageSnapshot.swift         # 用量快照模型
│   ├── Preferences.swift           # 偏好模型
│   ├── AuthBlob.swift              # 认证 blob 模型
│   └── AppState.swift              # 全局状态 (@Observable)
├── Services/
│   ├── CodexAppServer.swift        # JSON-RPC 子进程通信
│   ├── AccountStore.swift          # 文件持久化
│   ├── KeychainService.swift       # Keychain 读写
│   ├── AuthService.swift           # OAuth token 交换
│   └── UsageProbe.swift            # HTTP 用量探测
├── Utilities/
│   ├── JWTDecoder.swift            # JWT payload 解码
│   └── EmailMasker.swift           # 邮箱脱敏
└── Resources/
    └── Assets.xcassets             # 图标资源
```

## 数据模型

### Account

```swift
struct Account: Identifiable, Codable {
    let id: String
    var email: String
    var maskedEmail: String
    var planType: PlanType?
    var chatgptAccountId: String?
    var addedAt: Date
    var lastUsedAt: Date?
    var usageSnapshot: UsageSnapshot?
    var usageError: String?
    var isCurrent: Bool = false
}

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
    var label: String              // "5 Hours" 或 "Weekly"
    var windowDurationMins: Int
    var usedPercent: Double        // 0.0 ~ 100.0
    var resetsAt: Date?
}

struct Credits: Codable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}
```

### AuthBlob

```swift
struct AuthBlob: Codable {
    var authMode: String?
    var lastRefresh: String?
    var tokens: AuthTokens?
    var openaiApiKey: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case lastRefresh = "last_refresh"
        case tokens
        case openaiApiKey = "OPENAI_API_KEY"
    }
}

struct AuthTokens: Codable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountId = "account_id"
    }
}
```

## 核心服务协议

### CodexAppServer

与 `codex app-server` 子进程 JSON-RPC 通信：

- **启动**: `codex app-server --listen stdio://`
- **初始化**: `initialize` 请求，传入 `{ clientInfo: { name: "cx-switch", version: "0.1.0" }, protocolVersion: 2 }`
- **账户读取**: `account/read` → 返回 email、planType、requiresOpenaiAuth
- **用量读取**: `account/rateLimits/read` → 返回 primary/secondary 窗口用量
- **登录启动**: `account/login/start` → 返回 loginId、authUrl
- **登录取消**: `account/login/cancel`
- **登录完成**: `account/login/completed` 通知监听
- **超时**: 请求默认 20 秒，初始化 15 秒，登录等待 10 分钟
- **重试**: 启动失败重试 3 次，间隔 250ms 递增

### UsageProbe

直接 HTTP 探测用量（用于刷新已保存账户）：

- **URL**: `https://chatgpt.com/backend-api/codex/responses`
- **方法**: POST，发送最小请求 (model: gpt-5.1-codex, max_output_tokens: 1, store: false, stream: true)
- **认证**: Bearer token + chatgpt-account-id header
- **解析**: 响应头 `x-codex-{primary|secondary}-{used-percent|reset-after-seconds|window-minutes}`
- **超时**: 15 秒
- **并发**: 最多同时探测 2 个账户

### AuthService

OpenAI OAuth token 交换：

- **URL**: `https://auth.openai.com/oauth/token`
- **Client ID**: `app_EMoamEEZ73f0CkXaXp7hrann`
- **Grant Type**: `refresh_token`
- **Scope**: `openid profile email`

## UI 设计

### MenuBarView 面板布局

```
┌─────────────────────────────────────┐
│  ✦ user@email.com                    │
│  Pro Plan                            │
│                                      │
│  5 Hours  ████████░░  80%    1h30m   │  ← 原生 ProgressView
│  Weekly   ██░░░░░░░░  20%    3d      │  ← 原生 ProgressView
│                                      │
│  [Save Current Account]              │
├──────────────────────────────────────┤
│  Switch To                           │
│  ┌────────────────────────────────┐  │
│  │ other@mail.com  (plus)        │  │
│  │ ████░░░░░░ 40%               │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │ third@mail.com  (team)        │  │
│  │ ██████░░░░ 60%               │  │
│  └────────────────────────────────┘  │
├──────────────────────────────────────┤
│  ＋ Add Account…                     │
│  ↻  Refresh                          │
├──────────────────────────────────────┤
│  Settings…        OpenAI Status      │
│         Quit CX Switch               │
└──────────────────────────────────────┘
```

### UsageBar 进度条

- 使用原生 `ProgressView(value:total:)`
- 颜色规则: 0-60% → `.green`，60-85% → `.orange`，85-100% → `.red`
- 显示标签、百分比、重置倒计时

### 关键交互流程

**启动:**
1. 启动 `codex app-server` 并 `initialize`
2. 调用 `account/read` + `account/rateLimits/read` 获取当前账户
3. 加载 registry.json 获取已保存账户
4. 后台刷新过期快照（>60 秒）

**切换账户:**
1. 从 Keychain 读取目标 AuthBlob
2. 写入 `~/.codex/auth.json`
3. 重启 `codex app-server`
4. 刷新 UI

**添加账户:**
1. `account/login/start` → 获取 authUrl
2. `NSWorkspace.shared.open(url)` 打开浏览器
3. 等待 `account/login/completed` 通知（超时 10 分钟）
4. 成功后保存到 registry + Keychain

**导入 Refresh Token:**
1. 清理输入（去除引号/空白）
2. 调用 OpenAI OAuth 端点交换 token
3. 写入 auth.json → 重启 app-server
4. 读取账户信息 → 保存

## 应用配置

```
Bundle ID: com.bigo.cx-switch
App Name: CX Switch
LSUIElement: true          (无 Dock 图标)
Minimum Deployment: macOS 14.0
Swift: 6.0
Signing: Development
```

## Risks / Trade-offs

- [首版无测试] → 首版优先功能完整，后续迭代补充测试。
- [SwiftUI MenuBarExtra 在旧系统不可用] → 限定 macOS 14+ 规避兼容问题。
- [子进程管理不如 Bun 灵活] → Swift Process API 足够覆盖 stdio JSON-RPC 场景。
- [添加账户流程无内嵌 WebView] → 使用系统浏览器，体验略逊但实现简单可靠。

## Open Questions

- 是否需要支持从剪贴板粘贴 Refresh Token 的快捷操作？
- 面板宽度固定还是自适应内容？
- 是否需要 Sparkle 自动更新能力（后续版本）？
