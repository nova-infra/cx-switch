# CX Switch

CX Switch is a macOS menu bar app for managing and switching Codex accounts, refreshing usage data, and keeping a local cache of account state.

CX Switch 是一个 macOS 菜单栏应用，用来管理和切换 Codex 账号、刷新用量信息，并保留本地账号数据缓存。

## Features

- Menu bar only app powered by `MenuBarExtra`
- View current and saved accounts
- Switch, refresh, and re-authorize per account
- Import Refresh Token
- Cache account metadata, plan type, and usage snapshots locally
- Chinese-first UI with English fallback

## 功能

- 菜单栏常驻，使用 `MenuBarExtra`
- 查看当前账号和已保存账号
- 按账号切换、刷新、重新授权
- 导入 Refresh Token
- 本地缓存账号信息、套餐信息和用量信息
- 支持中文界面

## Development

### Requirements

- macOS
- Xcode 17+
- Swift 6

### Local Build

```bash
swift build
```

### Xcode Debug Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project /Users/Bigo/Desktop/develop/ai/cx-switch/CXSwitch.xcodeproj \
  -target CXSwitch -configuration Debug build
```

### Xcode Release Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project /Users/Bigo/Desktop/develop/ai/cx-switch/CXSwitch.xcodeproj \
  -target CXSwitch -configuration Release build
```

## 开发

### 依赖

- macOS
- Xcode 17+
- Swift 6

### 本地构建

```bash
swift build
```

### Xcode 构建

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project /Users/Bigo/Desktop/develop/ai/cx-switch/CXSwitch.xcodeproj \
  -target CXSwitch -configuration Debug build
```

### Release 构建

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project /Users/Bigo/Desktop/develop/ai/cx-switch/CXSwitch.xcodeproj \
  -target CXSwitch -configuration Release build
```

## Installer

After a Release build, generate a `.pkg` installer:

```bash
productbuild --component /Users/Bigo/Desktop/develop/ai/cx-switch/build/Release/CXSwitch.app \
  /Applications \
  /Users/Bigo/Desktop/develop/ai/cx-switch/build/Release/CXSwitch.pkg
```

## 安装包

Release 构建后，可以生成 `.pkg`：

```bash
productbuild --component /Users/Bigo/Desktop/develop/ai/cx-switch/build/Release/CXSwitch.app \
  /Applications \
  /Users/Bigo/Desktop/develop/ai/cx-switch/build/Release/CXSwitch.pkg
```

## Data Locations

The app reads and writes these local files:

- `~/Library/Application Support/com.novainfra.cx-switch/registry.json`
- `~/Library/Application Support/com.novainfra.cx-switch/preferences.json`
- `~/.codex/auth.json`

## 数据位置

应用会读取和写入以下本地数据：

- `~/Library/Application Support/com.novainfra.cx-switch/registry.json`
- `~/Library/Application Support/com.novainfra.cx-switch/preferences.json`
- `~/.codex/auth.json`

## Notes

- Account data is restored from local cache first, then refreshed from the app server
- Switching, usage refresh, and re-auth flows all depend on saved account records
- If an account is missing auth data, re-authorizing that account will usually restore `storedAuth`

## 说明

- 账号信息会优先从本地缓存恢复，再向 app-server 读取最新状态
- 切换账号、刷新用量、重新授权都依赖本地保存的账号记录
- 如果某条账号缺少认证信息，通常需要重新授权一次来补回 `storedAuth`
