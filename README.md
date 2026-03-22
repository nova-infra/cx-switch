# CX Switch

**English** | [中文](./README.zh.md)

**Switch between multiple ChatGPT / Codex accounts instantly from your Mac menu bar.**

CX Switch is a lightweight macOS menu bar utility that lets you manage and switch between multiple OpenAI accounts with a single click. No more logging in and out - your credentials are stored locally in an encrypted SQLite database.

## Features

- **Instant Switch** - Account switching completes in under 50ms
- **Per-Account Credentials** - Each account's auth is stored separately in local SQLite
- **Live Usage Tracking** - Real-time usage bars for 5-hour and weekly windows
- **Auto Refresh** - Usage data refreshes automatically when cooldowns expire
- **Native macOS** - Built with SwiftUI, lives in your menu bar, no Dock icon
- **Liquid Glass Ready** - Supports macOS Tahoe's Liquid Glass design language

## Install

### Homebrew (recommended)

```bash
brew install --cask cx-switch
```

### Direct download (DMG)

1. Download [**CXSwitch-v0.2.3.dmg**](https://github.com/nova-infra/cx-switch/releases/download/v0.2.3/CXSwitch-v0.2.3.dmg), open it, and drag **CXSwitch** into **Applications**.
2. If macOS shows a security warning or the app won’t open, clear quarantine flags:

```bash
xattr -cr /Applications/CXSwitch.app
```

### Build from source

Requires **Swift 6.0+** and **macOS 14+**.

```bash
git clone https://github.com/nova-infra/cx-switch.git
cd cx-switch
swift build -c release
cp .build/release/CXSwitch /usr/local/bin/
```

## How It Works

1. **Add accounts** - Log in to each ChatGPT account through the built-in auth flow
2. **Click to switch** - Select any account from the menu bar dropdown
3. **Codex picks it up** - The active account's credentials are written to `~/.codex/auth.json`, and Codex uses the new account automatically

## Security

- Credentials are stored **locally** in `~/Library/Application Support/com.novainfra.cx-switch/cx-switch.db`
- No data is sent to any third-party server
- Auth tokens are exchanged directly with `auth.openai.com`
- The source code is fully open for audit

## Requirements

- macOS 14 (Sonoma) or later
- Works with ChatGPT Plus, Team, and Enterprise accounts

## License

[Apache License 2.0](LICENSE)
