## Why

当前 CX Switch 使用 Electrobun (TypeScript/Bun) 构建，作为 macOS 菜单栏应用管理多个 OpenAI/ChatGPT 账户。但 Electrobun 的 Tray 菜单 API 只支持纯文本菜单项，无法渲染进度条、自定义视图等原生控件——这正是账户用量展示最需要的能力。

macOS 原生 SwiftUI 从 macOS 13 起提供 `MenuBarExtra`，支持完整的 SwiftUI 视图（ProgressView、自定义布局），且无需 Node/Bun 运行时，包体更小、启动更快、系统集成更深。

## What Changes

- **完整重写**：用 Swift 6 + SwiftUI 重写整个应用，替换 Electrobun/TypeScript/React 技术栈。
- **原生菜单栏体验**：使用 `MenuBarExtra(.window)` 样式渲染自定义面板，内含原生 ProgressView 进度条、账户列表、操作按钮。
- **保持数据兼容**：registry.json、auth.json、Keychain 存储格式与 Electrobun 版本完全兼容，用户无感切换。
- **保持后端协议**：继续通过 stdin/stdout JSON-RPC 与 `codex app-server` 子进程通信。

## Capabilities

### New Capabilities

- `swiftui-menubar-app`：原生 SwiftUI MenuBarExtra 应用，支持自定义视图渲染（ProgressView 进度条、账户卡片、操作按钮）。
- `native-keychain-integration`：使用 Security framework 直接访问 macOS Keychain，替换 shell 调用 `security` 命令。
- `native-process-management`：使用 Swift `Process` API 管理 `codex app-server` 子进程生命周期。

### Preserved Capabilities

- `codex-account-management`：多账户管理（添加、切换、删除、保存）能力保持不变。
- `usage-probe`：直接 HTTP 探测账户用量、解析响应头的能力保持不变。
- `oauth-token-exchange`：OpenAI OAuth refresh token 交换能力保持不变。

## Impact

- 删除全部 TypeScript/Bun/React 代码（src/bun、src/ui、src/shared、package.json 等）。
- 新建 Xcode 项目结构（CXSwitch/）。
- 数据层（registry.json、preferences.json、auth.json、Keychain）格式不变，零迁移成本。
- 构建工具从 `electrobun-vite` 切换为 Xcode / Swift Package Manager。
