# codex-account-management Specification

## MODIFIED Requirements

### Requirement: 系统 MUST 显示当前 Codex 账号用量
系统 SHALL 显示当前账号的用量信息，并优先使用该账号的缓存快照；当缓存存在时，面板应先展示缓存数据，再按需更新。当前账号还 SHALL 提供独立刷新入口，且刷新时只更新当前账号缓存。

#### Scenario: 用户查看当前账号用量
- **WHEN** 用户打开菜单栏面板
- **THEN** 显示当前账户邮箱、Plan 类型
- **AND** 显示 5 Hours 用量百分比 + 进度条 + 重置倒计时
- **AND** 显示 Weekly 用量百分比 + 进度条（若存在）
- **AND** 若该账号存在缓存快照，面板可先渲染缓存内容

#### Scenario: 用户刷新当前账号
- **WHEN** 用户点击当前账号摘要区的刷新入口
- **THEN** 仅当前账号的缓存失效并重新获取
- **AND** 已保存账户列表维持各自缓存
- **AND** 面板不触发全局重载

### Requirement: 用户 SHALL 可以在多个 Codex 账号间切换
系统 SHALL 支持在多个账号间切换，并在切换后仅刷新目标账号的缓存与当前账号状态，不影响其他账号的缓存结果。

#### Scenario: 用户切换账号
- **WHEN** 用户在已保存账户列表中点击另一个账号
- **THEN** 系统从 Keychain 读取该账号认证信息
- **AND** 写入 ~/.codex/auth.json
- **AND** 重启 codex app-server
- **AND** UI 刷新显示新账户信息
- **AND** 其他账号的缓存数据保持不变

### Requirement: 用量信息 MUST 支持手动刷新
系统 SHALL 提供按账号粒度的手动刷新能力；当用户刷新某个账号时，只重新获取该账号的用量与摘要数据，不应触发其他账号的重载。

#### Scenario: 用户刷新单个账号
- **WHEN** 用户点击某个账户条目的刷新入口
- **THEN** 仅该账户的缓存失效并重新获取
- **AND** 其他账户维持各自缓存
- **AND** 面板不因全局刷新而整体闪烁
