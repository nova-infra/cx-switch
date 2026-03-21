# codex-account-management Specification

## Purpose

定义 CX Switch 的多账户管理能力，包括查看、切换、添加、删除、保存、导入 Token。

## Requirements

### Requirement: 系统 MUST 显示当前 Codex 账号用量

#### Scenario: 用户查看当前账号用量
- **WHEN** 用户打开菜单栏面板
- **THEN** 显示当前账户邮箱、Plan 类型
- **AND** 显示 5 Hours 用量百分比 + 进度条 + 重置倒计时
- **AND** 显示 Weekly 用量百分比 + 进度条（若存在）

### Requirement: 用户 SHALL 可以在多个 Codex 账号间切换

#### Scenario: 用户切换账号
- **WHEN** 用户在已保存账户列表中点击另一个账号
- **THEN** 系统从 Keychain 读取该账号认证信息
- **AND** 写入 ~/.codex/auth.json
- **AND** 重启 codex app-server
- **AND** UI 刷新显示新账户信息

### Requirement: 用户 SHALL 可以保存当前账号

#### Scenario: 用户保存当前账号
- **WHEN** 当前账号未在注册表中
- **THEN** 面板显示 "Save Current Account" 按钮
- **WHEN** 用户点击该按钮
- **THEN** 认证信息保存到 Keychain
- **AND** 账户信息保存到 registry.json

### Requirement: 用户 SHALL 可以添加新账号

#### Scenario: 用户通过 OAuth 添加账号
- **WHEN** 用户点击 "Add Account"
- **THEN** 系统启动 ChatGPT OAuth 登录流程
- **AND** 打开系统浏览器
- **WHEN** 用户完成浏览器登录
- **THEN** 新账户自动保存到注册表和 Keychain

### Requirement: 用户 SHALL 可以通过 Refresh Token 导入账号

#### Scenario: 用户导入 Refresh Token
- **WHEN** 用户选择 "Import Refresh Token"
- **AND** 输入或粘贴 refresh token
- **THEN** 系统清理输入（去除引号、空白）
- **AND** 调用 OpenAI OAuth 端点交换 token
- **AND** 写入 auth.json 并重启 app-server
- **AND** 读取账户信息后保存到 registry + Keychain
- **AND** UI 刷新显示导入的账户

### Requirement: 用户 SHALL 可以删除已保存账号

#### Scenario: 用户删除已保存账号
- **WHEN** 用户对已保存账号执行删除操作
- **THEN** 从 registry.json 中移除
- **AND** 从 Keychain 中删除认证信息

### Requirement: 用量信息 MUST 支持手动刷新

#### Scenario: 用户手动刷新
- **WHEN** 用户点击 "Refresh"
- **THEN** 并发探测所有已保存账户的用量（并发度 2，超时 15 秒）
- **AND** 更新进度条和百分比

### Requirement: 用户 SHALL 可以切换邮箱脱敏

#### Scenario: 用户开启邮箱脱敏
- **WHEN** 用户在设置中开启 maskEmails
- **THEN** 所有邮箱显示为脱敏格式（如 `a••••z@gmail.com`）

### Requirement: 数据格式 MUST 与 Electrobun 版本兼容

#### Scenario: 用户从 Electrobun 版本切换
- **GIVEN** 用户已使用 Electrobun 版本保存了账户
- **WHEN** 用户启动 SwiftUI 版本
- **THEN** 已保存的账户数据正常加载
- **AND** Keychain 中的认证信息可正常读取
