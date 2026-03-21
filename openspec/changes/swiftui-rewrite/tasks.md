## 1. 项目初始化

- [ ] 1.1 创建 Xcode 项目 `CXSwitch`，配置 Bundle ID `com.novainfra.cx-switch`，最低部署目标 macOS 14.0
- [ ] 1.2 配置 `LSUIElement = true`（无 Dock 图标），设置 App icon
- [ ] 1.3 创建目录结构：Views/、Models/、Services/、Utilities/、Resources/

## 2. 数据模型

- [ ] 2.1 实现 `Account`、`PlanType`、`UsageSnapshot`、`UsageWindow`、`Credits` 模型（Codable，与 registry.json 兼容）
- [ ] 2.2 实现 `AuthBlob`、`AuthTokens` 模型（CodingKeys 映射 snake_case JSON 字段）
- [ ] 2.3 实现 `Preferences` 模型（含 `language` 字段，默认 `"zh"`，可选 `"en"`）
- [ ] 2.4 实现 `LoginFlowState` 模型

## 3. 基础服务

- [ ] 3.1 实现 `JWTDecoder`：Base64URL 解码 + JSON payload 提取
- [ ] 3.2 实现 `EmailMasker`：`a@b.com` → `a••••@b.com` 脱敏逻辑
- [ ] 3.3 实现 `KeychainService`：使用 Security framework 的 `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`，Service 为 `com.novainfra.cx-switch.account`，Value 为 Base64(AuthBlob JSON)
- [ ] 3.4 实现 `AccountStore`：registry.json 和 preferences.json 的加载/保存（原子写入），auth.json 读写
- [ ] 3.5 实现 `Strings.swift`：集中管理 UI 文案，每个字符串提供中文和英文版本，通过辅助函数 `L(_:en:)` 根据当前语言偏好返回对应文案

## 4. 后端通信服务

- [ ] 4.1 实现 `CodexAppServer`：`Process` 启动 `codex app-server --listen stdio://`，stdin/stdout JSON-RPC 通信
- [ ] 4.2 实现请求/响应匹配（基于 request id）、超时处理、通知监听
- [ ] 4.3 实现启动重试（3 次，间隔递增）、restart()、shutdown()
- [ ] 4.4 实现 `UsageProbe`：HTTP POST 探测用量，解析 `x-codex-*` 响应头，超时 15 秒，并发度 2
- [ ] 4.5 实现 `AuthService`：OpenAI OAuth refresh token 交换（URL: `https://auth.openai.com/oauth/token`，Client ID: `app_EMoamEEZ73f0CkXaXp7hrann`）

## 5. 应用状态

- [ ] 5.1 实现 `AppState`（@Observable），集成全部服务，持有 currentAccount、savedAccounts、preferences、loginFlow、refreshing 等状态
- [ ] 5.2 实现 `loadDashboard()`：启动 app-server → account/read → rateLimits/read → 加载 registry → 后台刷新
- [ ] 5.3 实现 `switchAccount(to:)`：Keychain 读取 → 写 auth.json → 重启 app-server → 刷新
- [ ] 5.4 实现 `saveCurrentAccount()`：保存当前账户到 registry + Keychain
- [ ] 5.5 实现 `removeAccount(_:)`：从 registry 和 Keychain 删除
- [ ] 5.6 实现 `refreshSavedAccounts(force:)`：并发探测已保存账户用量（过期阈值 60 秒）
- [ ] 5.7 实现 `startAddAccount()`：调用 login/start → 打开浏览器 → 等待 login/completed 通知
- [ ] 5.8 实现 `cancelAddAccount()`
- [ ] 5.9 实现 `importRefreshToken(_:)`：清理输入 → AuthService 交换 → 写 auth.json → 重启 app-server → 读取账户 → 保存到 registry + Keychain
- [ ] 5.10 实现 `setMaskEmails(_:)`、`openStatusPage()`、`openSettings()`、`quit()`

## 6. UI 视图

- [ ] 6.1 实现 `CXSwitchApp`：`@main` 入口，`MenuBarExtra("CX", systemImage:) { MenuBarView }.menuBarExtraStyle(.window)`
- [ ] 6.2 实现 `UsageBar`：ProgressView + 标签 + 百分比 + 重置倒计时，颜色规则（green/orange/red）
- [ ] 6.3 实现 `CurrentAccountSection`：当前账户邮箱、plan badge、UsageBar × 2、保存按钮
- [ ] 6.4 实现 `SavedAccountRow`：可点击账户行，含邮箱、plan badge、primary 用量条
- [ ] 6.5 实现 `MenuBarView`：组装 CurrentAccountSection + 已保存账户列表 + 添加/刷新/导入 + 错误提示 + Footer
- [ ] 6.6 实现 `LoginFlowSheet`：登录状态提示（准备中/等待中/已完成/出错）
- [ ] 6.7 实现 `FooterActions`：设置、OpenAI 状态、退出按钮
- [ ] 6.8 实现 Refresh Token 导入入口：提供"导入 Token…"操作，弹出输入框支持粘贴 token 并触发导入流程
- [ ] 6.9 所有视图文案从 `Strings.swift` 读取，不硬编码在视图中

## 7. 验证与收尾

- [ ] 7.1 Xcode build 通过，无 warning
- [ ] 7.2 验证 MenuBarExtra 面板显示、进度条渲染、账户切换流程
- [ ] 7.3 验证与 Electrobun 版本的数据兼容性（registry.json、Keychain 互通）
- [ ] 7.4 验证 Refresh Token 导入流程端到端可用
- [ ] 7.5 验证中文 UI 文案正确显示
- [ ] 7.6 清理旧文件，更新 .gitignore
