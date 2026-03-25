# Spec: 菜单滚动交互对齐 Quotio

## 目标

在保持 `MenuBarExtra(.window)` 的前提下，让 CX Switch 的菜单滚动体验对齐 Quotio 的原生 NSMenu 交互：
- 高度自适应内容（少账号时窗口小，多账号时窗口大）
- 超出最大高度时可滚动
- 无 scrollbar，用上下箭头指示可滚动方向（同 NSMenu）
- 滚动流畅，无卡顿

## 参考

Quotio（`/Users/Bigo/Desktop/develop/ai/quotio/Quotio/Services/StatusBarMenuBuilder.swift`）使用 NSMenu 原生滚动：
- 每个 NSMenuItem 通过 `NSHostingView.intrinsicContentSize` 自适应高度
- 菜单超出屏幕时 macOS 自动显示上下箭头（无 scrollbar）
- 宽度固定 320pt

## 当前问题

`MenuBarView.swift` 现状：
```swift
ScrollView(.vertical) {
    activePanel
        .padding(16)
        .frame(width: 360, alignment: .leading)
}
.frame(width: 360)
.frame(maxHeight: 560)
```

问题：
1. 内容套了两层 `frame(width: 360)`，padding 和 width 冲突
2. `maxHeight: 560` 固定上限，内容少时窗口也占满
3. 默认 ScrollView 显示系统 scrollbar，不像原生菜单
4. 无上下箭头指示

## 实现方案

### 文件：`CXSwitch/Views/MenuBarView.swift`

#### 1. 高度自适应

用 `GeometryReader` + `PreferenceKey` 测量内容真实高度，动态设置窗口高度：

```swift
@State private var contentHeight: CGFloat = 300  // 合理初始值

// 外层 frame 用 min(contentHeight, maxMenuHeight)
// maxMenuHeight = 560
```

#### 2. 隐藏 scrollbar

```swift
ScrollView(.vertical, showsIndicators: false) { ... }
```

#### 3. 上下箭头指示器

当内容超出 `maxMenuHeight` 时，在顶部/底部叠加箭头指示器：

```swift
// 用 ScrollViewReader + GeometryReader 检测滚动位置
// 顶部未到顶 → 显示上箭头 ▲
// 底部未到底 → 显示下箭头 ▼
// 箭头样式：半透明渐变背景 + chevron 图标，模拟 NSMenu 原生箭头
```

箭头视觉规格：
- 高度：20pt
- 背景：线性渐变（窗口背景色 → 透明）
- 图标：`chevron.compact.up` / `chevron.compact.down`，12pt，secondary 色
- 位置：overlay 在 ScrollView 顶部/底部

#### 4. 布局修正

```swift
ScrollView(.vertical, showsIndicators: false) {
    VStack(alignment: .leading, spacing: 14) {
        // 直接放内容，不再嵌套 frame(width:)
        CurrentAccountSection(...)
        sectionDivider
        // saved accounts...
        sectionDivider
        FooterActions(...)
    }
    .padding(16)
    .background {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
        }
    }
}
.frame(width: 360)
.frame(height: min(contentHeight, 560))
.onPreferenceChange(ContentHeightKey.self) { h in
    if h > 0 { contentHeight = h }
}
.overlay(alignment: .top) { topArrowIfNeeded }
.overlay(alignment: .bottom) { bottomArrowIfNeeded }
```

### 新增：`ContentHeightKey`

```swift
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

### 滚动位置检测

用 `ScrollView` 内的锚点 `GeometryReader` 检测是否到顶/到底：

```swift
// 在 VStack 第一个子视图前放一个透明锚点
Color.clear.frame(height: 0).id("top")
// 在最后一个子视图后放一个透明锚点
Color.clear.frame(height: 0).id("bottom")

// 在 ScrollView 的 coordinateSpace 中检测锚点位置
// atTop = topAnchorY >= 0
// atBottom = bottomAnchorY <= scrollViewHeight
```

### 箭头组件

```swift
private func scrollArrow(direction: ArrowDirection) -> some View {
    HStack {
        Spacer()
        Image(systemName: direction == .up ? "chevron.compact.up" : "chevron.compact.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        Spacer()
    }
    .frame(height: 20)
    .background(
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0)
            ],
            startPoint: direction == .up ? .top : .bottom,
            endPoint: direction == .up ? .bottom : .top
        )
    )
}
```

## 不改动的部分

- `CXSwitchApp.swift` — 保持 `MenuBarExtra(.window)` 不变
- `CurrentAccountSection.swift` / `SavedAccountRow.swift` / `FooterActions.swift` — 子视图不动
- `UsageBar.swift` — 不动

## 验证标准

1. `swift build` 通过
2. 1 个账号时：窗口高度贴合内容，无多余空白，无箭头
3. 5+ 个账号时：窗口高度 560pt 封顶，无 scrollbar，底部显示下箭头
4. 滚动到底时：下箭头消失，上箭头出现
5. 滚动流畅无卡顿
