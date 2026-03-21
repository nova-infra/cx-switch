## Why

首版 SwiftUI CX Switch 存在以下体验问题：
1. `codex app-server` 重启后 `account/read` 经常返回空——稳定性延迟不够，导致导入 Token、切换账号后显示"未检测到活跃账户"
2. `loadDashboard` 被面板开关反复触发，造成状态闪烁（进度条数量不稳定、账号信息时有时无）
3. 导入 Token 没有用户可感知的反馈（成功/失败都没有提示）
4. 用量进度条在 secondary 为空时布局不一致
5. 面板缺少整体 loading 状态，用户不知道操作是否在进行中

## What Changes

- 修复 app-server 重启后的就绪检测机制
- 防止 `loadDashboard` 并发和重复触发
- 为所有异步操作增加用户可感知的状态反馈
- 统一进度条布局，处理只有一个窗口的场景
- 整体优化面板交互体验
