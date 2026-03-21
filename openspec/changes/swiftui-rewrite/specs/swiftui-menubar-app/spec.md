# swiftui-menubar-app Specification

## Purpose

定义 CX Switch 作为 macOS 原生 SwiftUI MenuBarExtra 应用的 UI 和交互规格。

## Requirements

### Requirement: 应用 MUST 以菜单栏图标形式运行，无 Dock 图标

#### Scenario: 用户启动应用
- **WHEN** 应用启动
- **THEN** 菜单栏出现 "CX" 图标
- **AND** Dock 中无应用图标 (LSUIElement = true)

### Requirement: 点击菜单栏图标 MUST 弹出自定义面板

#### Scenario: 用户点击菜单栏图标
- **WHEN** 用户点击 "CX" 图标
- **THEN** 弹出 SwiftUI 自定义面板 (MenuBarExtra .window 样式)
- **AND** 面板包含当前账户、已保存账户列表、操作按钮

### Requirement: 用量 MUST 以原生进度条形式显示

#### Scenario: 用户查看账户用量
- **WHEN** 面板显示当前账户或已保存账户
- **THEN** 用量以原生 ProgressView 渲染
- **AND** 显示标签名（5 Hours / Weekly）、百分比、重置倒计时
- **AND** 颜色规则：0-60% 绿色、60-85% 橙色、85-100% 红色

### Requirement: 面板 MUST 在失去焦点时自动关闭

#### Scenario: 用户点击面板外区域
- **WHEN** 面板失去焦点
- **THEN** 面板自动关闭
