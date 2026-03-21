## Context

CX Switch SwiftUI 版首轮测试发现若干稳定性和体验问题。核心是 `codex app-server` 子进程在 restart 后需要一定时间才能响应 `account/read`，而当前代码等待时间不够且缺少重试机制，导致账号信息频繁丢失。

## Goals / Non-Goals

**Goals:**
- app-server restart 后稳定读到当前账号
- 所有异步操作（导入、切换、刷新）有明确的 UI 反馈
- 面板状态稳定，不闪烁
- 进度条布局一致

**Non-Goals:**
- 不改变数据模型或存储格式
- 不新增功能

## Decisions

### 1. app-server 就绪检测：重试轮询替代固定延迟

当前 `restartStabilizationDelay` 用固定等待，但 app-server 启动时间不稳定。

**改为：** restart 后轮询 `account/read`，最多重试 5 次，每次间隔 1 秒，直到返回有效账号或超时。

实现位置：`AppState.swift`，新增 `waitForAccountReady()` 方法：

```swift
private func waitForAccountReady(authBlob: AuthBlob?) async -> Account? {
    for attempt in 1...5 {
        NSLog("[CXSwitch] waitForAccountReady: attempt %d", attempt)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if let account = try? await fetchCurrentAccountOnce(fromAuth: authBlob) {
            return account
        }
    }
    return nil
}
```

所有需要 restart 的操作（`importRefreshToken`、`switchAccount`、`loadDashboard`）统一使用此方法。

### 2. loadDashboard 防并发 + 仅首次加载

**问题：** MenuBarExtra 的 `.task` modifier 在面板每次显示时触发，导致 `loadDashboard` 被重复调用，状态闪烁。

**改为：**
- `AppState` 增加 `dashboardLoaded: Bool` 标记，`loadDashboard` 仅在 `false` 时执行
- 面板关闭再打开不重新加载（除非手动刷新）
- `importRefreshToken`、`switchAccount` 完成后直接设置状态，不调用 `loadDashboard`

实现位置：`AppState.swift`

```swift
func loadDashboard() async {
    guard !dashboardLoaded else { return }
    // ... existing logic ...
    dashboardLoaded = true
}
```

### 3. 操作状态反馈

每个异步操作需要用户可感知的反馈：

| 操作 | 进行中 | 成功 | 失败 |
|------|--------|------|------|
| 导入 Token | 显示 "正在导入…" + ProgressView | 当前账户更新 + 简短提示 "已导入 xxx@email.com" | 红色错误文字 |
| 切换账号 | 显示 "正在切换…" + ProgressView | 当前账户更新 + 提示 "已切换到 xxx" | 红色错误文字 |
| 刷新 | 已有 refreshing 状态 | 无需额外提示 | 红色错误文字 |

实现：`AppState` 新增 `statusMessage: String?`，在操作完成时设置，UI 显示在错误信息同一位置（绿色或默认颜色）。3 秒后自动清空。

```swift
var statusMessage: String?

private func showStatus(_ message: String) {
    statusMessage = message
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if statusMessage == message { statusMessage = nil }
    }
}
```

实现位置：`AppState.swift`（状态）、`MenuBarView.swift`（显示）

### 4. 进度条布局修复

**问题：** 当只有 primary 没有 secondary 时，HStack 里只有一个 UsageBar，占据半宽，看起来不对称。

**改为：** CurrentAccountSection 里判断窗口数量：
- 两个窗口：`HStack` 左右并排
- 一个窗口：单独一行全宽

```swift
if let snapshot = account.usageSnapshot {
    let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
    if windows.count == 2 {
        HStack(spacing: 12) {
            UsageBar(window: windows[0])
            UsageBar(window: windows[1])
        }
    } else if let single = windows.first {
        UsageBar(window: single)
    }
}
```

实现位置：`CurrentAccountSection.swift`

### 5. CodexAppServer.restart 改为异步

当前 `restart()` 是同步的（`shutdown()` + `start()`），但 start 后 app-server 还没真正就绪。

**改为：** `restart()` 变成 `async`，内部 shutdown → start → initialize，调用方不再需要手动 initialize。

```swift
func restartAndInitialize() async throws {
    shutdown()
    try await Task.sleep(nanoseconds: 500_000_000)
    try start()
    try await initialize()
}
```

实现位置：`CodexAppServer.swift`
