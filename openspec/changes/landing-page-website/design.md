## Context

CX Switch 是 macOS 菜单栏工具，用于在多个 ChatGPT / Codex 账号之间快速切换。当前无公开网站，分发依赖口口相传。产品定位是面向重度 AI 用户（开发者、团队管理员、多账号用户）的效率工具。

## Goals / Non-Goals

**Goals:**
- 单页面落地站，首屏 3 秒内传达产品价值
- 响应式布局，兼容 Desktop / Mobile
- 快速加载（< 100KB HTML+CSS，无 JS 框架）
- 支持中文/英文双语（默认英文，中文可选）
- 提供明确的下载 CTA（Call to Action）
- 支持 GitHub Pages 零成本部署

**Non-Goals:**
- 不做用户系统 / 登录
- 不做在线文档（README 够用）
- 不做博客系统
- 不做付费 / 订阅流程

## Decisions

### 1. 技术栈

纯静态站：**HTML + Tailwind CSS (CDN)** + 少量 vanilla JS（语言切换、滚动动画）。

理由：
- 无构建工具，任何人 clone 后直接打开 `index.html` 即可预览
- Tailwind CDN 提供完整的设计系统，不用写自定义 CSS
- 零运行时依赖，GitHub Pages 直接部署

### 2. 页面结构

```
┌─────────────────────────────────────────┐
│  Nav: Logo + CX Switch + [EN/中文] + ★ GitHub  │
├─────────────────────────────────────────┤
│  Hero                                   │
│  "Switch ChatGPT accounts              │
│   in one click."                        │
│  [Download for macOS]  [View on GitHub] │
│  App screenshot (menu bar popover)      │
├─────────────────────────────────────────┤
│  Features (3-column grid)               │
│  ⚡ Instant Switch   🔒 Per-Account     │
│     < 50ms latency      Credentials     │
│  📊 Live Usage       🔄 Auto Refresh   │
│     Real-time bars      On cooldown     │
│  🛡️ SQLite Store    🎨 Liquid Glass    │
│     Encrypted local     macOS native    │
├─────────────────────────────────────────┤
│  How It Works (3 steps)                 │
│  1. Add accounts → 2. Click switch →   │
│  3. Codex uses new account              │
├─────────────────────────────────────────┤
│  Screenshot Gallery                     │
│  (Dashboard / Settings / Switch anim)   │
├─────────────────────────────────────────┤
│  Install                                │
│  brew install --cask cx-switch          │
│  — or —                                 │
│  Download DMG                           │
├─────────────────────────────────────────┤
│  FAQ                                    │
│  - Is it free?                          │
│  - Where are credentials stored?        │
│  - Does it work with ChatGPT Teams?     │
├─────────────────────────────────────────┤
│  Footer: © 2026 · GitHub · License      │
└─────────────────────────────────────────┘
```

### 3. 视觉风格

- **色调**: 深色主题（与 macOS 菜单栏风格一致），accent 用系统蓝 `#007AFF`
- **字体**: `Inter`（英文）+ 系统字体 fallback（中文）
- **截图**: 带 macOS 窗口 chrome 的真实截图，加轻微阴影
- **动画**: 仅 `scroll-driven` 淡入，不用复杂动画库

### 4. 双语方案

用 `data-lang` 属性 + 少量 JS 切换 `display`：

```html
<h1>
  <span data-lang="en">Switch ChatGPT accounts in one click.</span>
  <span data-lang="zh" hidden>一键切换 ChatGPT 账号。</span>
</h1>
```

语言偏好存 `localStorage`，默认英文。

### 5. 部署

- 代码放 `docs/` 目录或独立仓库
- GitHub Pages 从 `main` 分支 `/docs` 目录发布
- 自定义域名（可选）：`cxswitch.dev` 或类似

## 文件结构

```
docs/
├── index.html          # 主页面（所有内容）
├── style.css           # 少量自定义样式（Tailwind 不覆盖的）
├── script.js           # 语言切换 + 滚动动画（< 50 行）
├── assets/
│   ├── icon.png        # App 图标
│   ├── hero.png        # Hero 区域截图
│   ├── feature-*.png   # 功能截图
│   └── og-image.png    # Open Graph 分享图
└── CNAME               # 自定义域名（可选）
```
