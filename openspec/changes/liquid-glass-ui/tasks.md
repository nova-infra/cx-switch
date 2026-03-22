## 1. 兼容适配层

- [x] 1.1 新增 `CXSwitch/Utilities/GlassCompat.swift`，包含：
  - `View.adaptiveGlass(cornerRadius:)` — macOS 26 用 `.glassEffect(.regular)`，旧系统用 `.thinMaterial` + `strokeBorder`
  - `View.adaptiveGlassTint(_:in:)` — macOS 26 用 `.glassEffect(.regular.tint())`，旧系统用 `color.opacity(0.15)`
  - `View.adaptiveGlassCircle()` — macOS 26 用 `.glassEffect(.regular, in: Circle())`，旧系统用 `Color.primary.opacity(0.06)` Circle
  - `AdaptiveGlassContainer` — macOS 26 用 `GlassEffectContainer`，旧系统用普通容器透传
- [ ] 1.2 `swift build` 通过，`#available(macOS 26, *)` 分支编译正确

## 2. CXSwitchApp

- [x] 2.1 MenuBarExtra label 图标加 `.renderingMode(.template)`

## 3. CurrentAccountSection

- [x] 3.1 移除 `.background(.thinMaterial, in: RoundedRectangle(...))` 和 `.overlay(strokeBorder(...))`（第 62-66 行）
- [x] 3.2 替换为 `.adaptiveGlass()`
- [x] 3.3 刷新按钮：`.background(.regularMaterial, in: Circle())`（第 82 行）替换为 `.adaptiveGlassCircle()`

## 4. SavedAccountRow

- [x] 4.1 刷新按钮：`.background(Color.primary.opacity(0.06), in: Circle())`（第 58 行）替换为 `.adaptiveGlassCircle()`

## 5. SettingsView

- [x] 5.1 设置卡片背景：移除 `.background(.thinMaterial, ...)` + `.overlay(strokeBorder(...))`（第 37-41 行）
- [x] 5.2 替换为 `.adaptiveGlass()`

## 6. FooterActions

- [x] 6.1 `LazyVGrid` 外层包裹 `AdaptiveGlassContainer { ... }`

## 7. LoginFlowSheet

- [x] 7.1 Sheet 内容 VStack 加 `.adaptiveGlass(cornerRadius: 16)`

## 8. 清理验证

- [x] 8.1 全局搜索确认 View 层无直接使用 `.thinMaterial`、`.regularMaterial`（GlassCompat 内部除外）
- [x] 8.2 全局搜索确认无 `Color.primary.opacity(0.05/0.06)` 手动背景（GlassCompat 内部除外）
- [x] 8.3 `swift build` 通过
- [ ] 8.4 macOS 14/15 运行正常（现有效果不变）
  - 打开菜单栏面板，确认当前账户卡片、设置卡片和登录 sheet 仍保持原有毛玻璃观感
  - 确认刷新按钮、切换高亮和 footer 按钮的交互状态没有出现边框错位或背景溢出
- [ ] 8.5 macOS 26 运行正常（如有环境）
  - 打开同一组界面，确认 Liquid Glass 折射与高光已生效
  - 确认 `AdaptiveGlassContainer`、`adaptiveGlass()`、`adaptiveGlassCircle()` 的 fallback 未在新系统上混入
