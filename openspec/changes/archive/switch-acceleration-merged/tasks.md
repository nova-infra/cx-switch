## 1. 切换与导入流程

- [x] 1.1 `AppState.swift` 将账号切换改为乐观更新当前账号，再后台等待 `account/read`
- [x] 1.2 `AppState.swift` 将 refresh token 导入改为两阶段流程：先写 auth，再后台补齐账号信息
- [x] 1.3 `AppState.swift` 为乐观切换和导入完成增加明确的状态消息

## 2. 后台同步与持久化

- [x] 2.1 `AppState.swift` 将 `account/read` 就绪等待改为渐进式退避
- [x] 2.2 `AppState.swift` 合并 live 账号数据时保留 `storedAuth` 和 registry-only 字段
- [x] 2.3 `AccountStore.swift` 为 registry 写入增加短时合并或防抖

## 3. UI 交互优化

- [x] 3.1 `MenuBarView.swift` 将全局 loading 收敛为更轻量的状态展示
- [x] 3.2 `CurrentAccountSection.swift` 与 `SavedAccountRow.swift` 保持按账号粒度的刷新反馈
- [x] 3.3 快速连续切换时保持其它账号可交互

## 4. 验证

- [x] 4.1 `swift build` 通过
- [ ] 4.2 切换账号后 UI 立即更新，live 数据稍后补齐
- [ ] 4.3 导入 Token 后先看到新账号，再后台补齐元数据
- [ ] 4.4 快速连续切换不会阻塞整个面板
- [ ] 4.5 registry 写入不会在短时间内重复刷盘
