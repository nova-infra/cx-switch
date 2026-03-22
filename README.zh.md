# CX Switch

![CX Switch — Mac 菜单栏 ChatGPT / Codex 多账号切换](banner.jpg)

**中文** | [English](./README.md)

**在 Mac 菜单栏里，一键切换多个 ChatGPT / Codex 账号。**

CX Switch 是一款轻量 macOS 菜单栏工具，可集中管理并在多个 OpenAI 账号之间一键切换，无需反复登入登出；凭证加密保存在本地 SQLite 数据库中。

## 功能亮点

- **极速切换** - 账号切换在 50 毫秒内完成
- **分账户凭证** - 每个账号的鉴权信息单独保存在本地 SQLite
- **实时用量** - 5 小时与周窗口的用量条
- **自动刷新** - 冷却结束后自动刷新用量数据
- **原生 macOS** - SwiftUI 编写，常驻菜单栏，无 Dock 图标
- **Liquid Glass** - 适配 macOS Tahoe Liquid Glass 设计语言

## 安装

### Homebrew（推荐）

```bash
brew install --cask cx-switch
```

### 直接下载（DMG）

1. 下载 [**CXSwitch-v0.2.3.dmg**](https://github.com/nova-infra/cx-switch/releases/download/v0.2.3/CXSwitch-v0.2.3.dmg)，打开后将 **CXSwitch** 拖入 **应用程序**。
2. 若出现安全提示或无法打开，在终端执行：

```bash
xattr -cr /Applications/CXSwitch.app
```

### 从源码构建

需要 **Swift 6.0+** 与 **macOS 14+**。

```bash
git clone https://github.com/nova-infra/cx-switch.git
cd cx-switch
swift build -c release
cp .build/release/CXSwitch /usr/local/bin/
```

## 使用方式

1. **添加账号** - 通过内置登录流程登录各 ChatGPT 账号
2. **点击切换** - 在菜单栏下拉里选择目标账号
3. **Codex 自动读取** - 当前账号凭证写入 `~/.codex/auth.json`，Codex 会使用新账号

## 安全说明

- 凭证**仅保存在本机**：`~/Library/Application Support/com.novainfra.cx-switch/cx-switch.db`
- 不向第三方服务器上传凭证数据
- 鉴权 token 直接与 `auth.openai.com` 交换
- 源码完全开放，可自行审计

## 系统要求

- macOS 14（Sonoma）或更新版本
- 适用于 ChatGPT Plus、Team、Enterprise 等账号

## 许可证

[Apache License 2.0](LICENSE)
