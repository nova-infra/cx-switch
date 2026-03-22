## Why

当前账号切换和刷新流程会先写 auth、重启 app-server、再轮询账号是否就绪，导致切换体感偏慢。需要把“看起来切过去”和“后台补齐数据”解耦，在不牺牲正确性的前提下显著降低等待感。

## What Changes

- 将账号切换改为“乐观切换 + 后台同步”：先更新当前账号 UI，再异步等待 `account/read`
- 将 refresh token 导入改为两阶段：先完成认证写入，再后台补齐账户元数据
- 将 registry 持久化改为短时间合并写入，减少频繁磁盘落盘
- 将账号就绪轮询改为渐进式退避，避免固定等待带来的卡顿感
- 将刷新状态收敛为按账号粒度，避免一个账号刷新影响整个面板交互

## Capabilities

### New Capabilities
- `account-switch-acceleration`: 定义更快的账号切换、导入和后台同步行为

### Modified Capabilities
- 

## Impact

- `CXSwitch/Models/AppState.swift`
- `CXSwitch/Services/AccountStore.swift`
- `CXSwitch/Services/CodexAppServer.swift`
- `CXSwitch/Views/MenuBarView.swift`
- `CXSwitch/Views/SavedAccountRow.swift`
- `CXSwitch/Views/CurrentAccountSection.swift`
- registry 写入和读取的时序
- 账号切换与导入的用户感知延迟
