## 1. 数据模型

- [x] 1.1 `Preferences.swift` 新增 `theme: String?` 字段，默认 `"system"`，可选值 `"system"` / `"light"` / `"dark"`
- [x] 1.2 `AppState.swift` 新增 `setTheme(_:)` 方法：更新 `preferences.theme` → `applyTheme()` → 保存偏好
- [x] 1.3 `AppState.swift` 新增 `applyTheme()` 私有方法：根据 theme 值设置 `NSApp.appearance`（`nil` / `.aqua` / `.darkAqua`）
- [x] 1.4 `AppState.swift` 新增 `setLanguage(_:)` 方法：更新 `preferences.language` → `applyPreferencesSideEffects()` → 保存偏好
- [x] 1.5 `loadDashboard` 中 preferences 加载后调用 `applyTheme()`

## 2. Strings 新增

- [x] 2.1 新增 `language`、`theme`、`themeSystem`、`themeLight`、`themeDark` 字符串
- [x] 2.2 新增 `languageChinese`（固定 "中文"）、`languageEnglish`（固定 "English"）
- [x] 2.3 新增 `openaiStatus` 字符串

## 3. SettingsView 新建

- [x] 3.1 新建 `CXSwitch/Views/SettingsView.swift`
- [x] 3.2 顶部：← 返回按钮 + "设置" 标题
- [x] 3.3 Toggle：邮箱脱敏开关，绑定 `state.preferences.maskEmails`，调用 `state.setMaskEmails(_:)`
- [x] 3.4 Picker（Segmented 或 inline）：语言选择，`中文` / `English`，调用 `state.setLanguage(_:)`
- [x] 3.5 Picker（Segmented 或 inline）：主题选择，`跟随系统` / `亮色` / `暗色`，调用 `state.setTheme(_:)`
- [x] 3.6 Divider
- [x] 3.7 Button：OpenAI 状态 →，调用 `state.openStatusPage()`
- [x] 3.8 Button：打开配置文件夹 →，调用 `state.openSettings()`

## 4. FooterActions 精简

- [x] 4.1 移除"状态"、"邮箱脱敏"按钮（移到设置面板）
- [x] 4.2 保留 4 个按钮：添加账户、导入 Token、设置、退出
- [x] 4.3 2×2 网格布局
- [x] 4.4 移除 `maskEmails` / `onToggleMaskEmails` / `onOpenStatus` 参数

## 5. MenuBarView 切换逻辑

- [x] 5.1 新增 `@State private var showSettings = false`
- [x] 5.2 `body` 根据 `showSettings` 显示 `mainPanel` 或 `SettingsView(onBack: { showSettings = false })`
- [x] 5.3 FooterActions 的 `onOpenSettings` 改为 `{ showSettings = true }`
- [x] 5.4 确保设置面板和主面板共享同一个 frame width

## 6. 验证

- [x] 6.1 `swift build` 通过
- [ ] 6.2 首页只显示 4 个按钮，布局整齐
- [ ] 6.3 点击设置 → 切换到设置面板 → 各开关/选项可操作 → 返回回到首页
- [ ] 6.4 语言切换：中文 ↔ English，UI 文字即时更新
- [ ] 6.5 主题切换：跟随系统 / 亮色 / 暗色，面板外观即时变化
- [ ] 6.6 邮箱脱敏开关生效
- [ ] 6.7 OpenAI 状态链接打开浏览器
- [ ] 6.8 打开配置文件夹打开 Finder
