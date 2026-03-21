## 1. app-server 就绪检测

- [x] 1.1 在 `AppState.swift` 新增 `waitForAccountReady(authBlob:) -> Account?` 方法：restart 后轮询 `account/read` 最多 5 次，间隔 1 秒，返回有效账号或 nil
- [x] 1.2 在 `CodexAppServer.swift` 新增 `restartAndInitialize() async throws` 方法：shutdown → sleep 500ms → start → initialize，一步到位
- [x] 1.3 `importRefreshToken` 使用 `restartAndInitialize()` + `waitForAccountReady()`，去掉手动 restart/initialize/sleep 拼接
- [x] 1.4 `switchAccount` 使用 `restartAndInitialize()` + `waitForAccountReady()`，去掉手动 restart/initialize/sleep 拼接
- [x] 1.5 `loadDashboard` 中 `fetchCurrentAccount` 失败时重试一次（间隔 1 秒）

## 2. 防止 loadDashboard 重复触发

- [x] 2.1 `AppState` 新增 `dashboardLoaded: Bool`，`loadDashboard` 仅在 `false` 时执行，执行完设为 `true`
- [x] 2.2 `importRefreshToken` 和 `switchAccount` 完成后直接更新 `currentAccount` 和 `savedAccounts`，不再调用 `loadDashboard`
- [x] 2.3 新增 `forceReloadDashboard()` 方法忽略 `dashboardLoaded` 标记，供"刷新"按钮使用
- [x] 2.4 MenuBarView 的 `.task` 只调用 `loadDashboard()`（受 dashboardLoaded 保护，不会重复）

## 3. 操作状态反馈

- [x] 3.1 `AppState` 新增 `statusMessage: String?` 和 `showStatus(_:)` 方法（3 秒后自动清空）
- [x] 3.2 `importRefreshToken` 成功后调用 `showStatus("已导入 xxx@email.com")`
- [x] 3.3 `switchAccount` 成功后调用 `showStatus("已切换到 xxx@email.com")`
- [x] 3.4 `MenuBarView` 在错误信息区域增加 `statusMessage` 显示（绿色字体，与 errorMessage 互斥）
- [x] 3.5 `importRefreshToken` 和 `switchAccount` 执行期间设置 `refreshing = true`，面板显示 ProgressView

## 4. 进度条布局修复

- [x] 4.1 `CurrentAccountSection` 根据可用窗口数量决定布局：2 个并排 HStack，1 个单独全宽
- [x] 4.2 `SavedAccountRow` 同样处理：只有 primary 时全宽显示

## 5. 验证

- [x] 5.1 `swift build` 通过无 warning
- [x] 5.2 测试导入 Token 流程：粘贴 → 确认 → 显示"正在导入…" → 成功后显示新账号 + 状态提示
- [x] 5.3 测试切换账号：点击 → 显示"正在切换…" → 成功后当前账号更新
- [x] 5.4 测试面板开关：多次打开关闭面板，状态不闪烁，进度条数量稳定
- [x] 5.5 测试只有 primary 没有 secondary 的账号，进度条全宽显示
