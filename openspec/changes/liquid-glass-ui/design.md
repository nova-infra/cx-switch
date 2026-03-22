## Context

CX Switch 面板当前样式现状（settings-consolidation 之后）：

- `CurrentAccountSection`: `.thinMaterial` + `RoundedRectangle(cornerRadius: 18)` + `strokeBorder(opacity: 0.06)`
- `SavedAccountRow`: 无背景容器，刷新按钮用 `Color.primary.opacity(0.06)` Circle
- `FooterActions`: 4 个按钮（添加、导入、设置、退出），`.buttonStyle(.plain)` + LazyVGrid
- `SettingsView`: `.thinMaterial` 背景卡片 + segmented pickers + actionRow 按钮
- `LoginFlowSheet`: 无特殊背景

## Goals / Non-Goals

**Goals:**
- macOS 26 自动获得 Liquid Glass（折射、高光、自适应阴影）
- macOS 14/15 保持现有 `.thinMaterial` 效果
- 最低部署目标保持 macOS 14 不变
- View 层代码不出现 `#available`，全部通过 GlassCompat 封装

**Non-Goals:**
- 不改功能逻辑
- 不引入自定义动画

## Decisions

### 1. GlassCompat.swift — 条件适配层

新增 `CXSwitch/Utilities/GlassCompat.swift`（~70 行），封装全部 Liquid Glass API：

```swift
import SwiftUI

// MARK: - 容器玻璃效果
extension View {
    @ViewBuilder
    func adaptiveGlass(
        cornerRadius: CGFloat = 18
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(shape.fill(.thinMaterial))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    @ViewBuilder
    func adaptiveGlassTint(
        _ color: Color,
        in shape: some Shape = Capsule()
    ) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(color), in: shape)
        } else {
            self.background(color.opacity(0.15), in: shape)
        }
    }

    @ViewBuilder
    func adaptiveGlassCircle() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self.background(Color.primary.opacity(0.06), in: Circle())
        }
    }
}

// MARK: - 按钮样式
struct AdaptiveGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // macOS 26: .glass 按钮样式需要在调用点用 if #available
        // 这里提供统一的 fallback
        configuration.label
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - 容器
struct AdaptiveGlassContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
```

### 2. 各组件迁移对照表

| 组件 | 当前代码 | 替换为 |
|------|----------|--------|
| **CurrentAccountSection** 背景 | `.background(.thinMaterial, in: RoundedRectangle(...))` + `.overlay(strokeBorder)` | `.adaptiveGlass()` |
| **CurrentAccountSection** 刷新按钮 | `.background(.regularMaterial, in: Circle())` | `.adaptiveGlassCircle()` |
| **SavedAccountRow** 刷新按钮 | `.background(Color.primary.opacity(0.06), in: Circle())` | `.adaptiveGlassCircle()` |
| **SettingsView** 卡片背景 | `.background(.thinMaterial, in: RoundedRectangle(...))` + `.overlay(strokeBorder)` | `.adaptiveGlass()` |
| **FooterActions** 整体 | `LazyVGrid { ... }` 无容器 | `AdaptiveGlassContainer { LazyVGrid { ... } }` |
| **FooterActions** 按钮 | `.buttonStyle(.plain)` | 保持 `.plain`（macOS 26 下 `AdaptiveGlassContainer` 已提供玻璃层）|
| **LoginFlowSheet** 背景 | 无 | `.adaptiveGlass(cornerRadius: 16)` |
| **CXSwitchApp** 图标 | `systemImage: "bolt.circle"` | 加 `.renderingMode(.template)` |

### 3. 不改的部分

- `UsageBar` — 内容层，不加玻璃
- `ProgressView` — 保持原生样式
- 错误/状态文字 — 纯文本
- 部署目标 — macOS 14

## 文件修改范围

| 文件 | 改动量 | 内容 |
|------|--------|------|
| **新增** `Utilities/GlassCompat.swift` | ~70 行 | 适配层 |
| `CXSwitchApp.swift` | 1 行 | `.renderingMode(.template)` |
| `CurrentAccountSection.swift` | 3 行 | 移除 `.background` + `.overlay`，替换为 `.adaptiveGlass()`；刷新按钮 `.adaptiveGlassCircle()` |
| `SavedAccountRow.swift` | 1 行 | 刷新按钮 `.adaptiveGlassCircle()` |
| `SettingsView.swift` | 3 行 | 移除 `.background` + `.overlay`，替换为 `.adaptiveGlass()` |
| `FooterActions.swift` | 2 行 | 外层包 `AdaptiveGlassContainer` |
| `LoginFlowSheet.swift` | 1 行 | 加 `.adaptiveGlass(cornerRadius: 16)` |
| `UsageBar.swift` | 0 行 | **不改** |
