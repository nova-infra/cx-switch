## Why

macOS Tahoe (macOS 26) 引入 Liquid Glass 设计语言。CX Switch 当前使用 `.thinMaterial` + 手动 opacity border 模拟毛玻璃，升级后可获得真正的光线折射效果，与系统风格完全一致。

采用兼容模式：macOS 26 用户自动获得 Liquid Glass，macOS 14/15 保持现有效果。最低部署目标不变。

## What Changes

- 新增 `GlassCompat.swift` 条件适配层，封装 `#available(macOS 26, *)` 判断
- 所有 View 的材质背景、按钮样式通过适配层调用
- macOS 26: `.glassEffect()` + `.buttonStyle(.glass)` + `GlassEffectContainer`
- macOS 14/15: `.thinMaterial` + `.buttonStyle(.plain)` + 普通容器（现有效果）

## Impact

- 新增 1 个文件（~60 行）
- 修改 7 个 View 文件（每个改 2-5 行）
- 不改数据模型、服务层、业务逻辑
- 部署目标保持 macOS 14
