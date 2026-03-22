## 1. 项目初始化

- [x] 1.1 创建 `docs/` 目录
- [x] 1.2 添加 `index.html` 骨架（HTML5 + Tailwind CDN + meta tags + Open Graph）
- [x] 1.3 添加 `style.css`（自定义滚动条、selection 颜色等 Tailwind 不覆盖的细节）
- [x] 1.4 添加 `script.js`（语言切换逻辑 + IntersectionObserver 滚动淡入）

## 2. 素材准备

- [x] 2.1 导出 App 图标 `icon.png`（512x512 + 128x128）
- [x] 2.2 截取 Hero 区域截图（菜单栏弹出面板，带 macOS chrome）
- [x] 2.3 截取功能截图（Dashboard 用量条、设置页、切换动画）
- [x] 2.4 制作 Open Graph 分享图 `og-image.png`（1200x630）

## 3. Hero 区域

- [x] 3.1 Logo + 产品名 + 一句话描述
- [x] 3.2 主 CTA 按钮：Download for macOS（链接到 GitHub Releases / DMG）
- [x] 3.3 副 CTA 按钮：View on GitHub（链接到仓库，仓库公开后生效）
- [x] 3.4 Hero 截图（带阴影 + 浮动效果）

## 4. Features 区域

- [x] 4.1 6 宫格功能卡片（Instant Switch / Per-Account Credentials / Live Usage / Auto Refresh / SQLite Store / Liquid Glass）
- [x] 4.2 每张卡片：图标 + 标题 + 一行描述
- [x] 4.3 中英文内容

## 5. How It Works 区域

- [x] 5.1 三步流程（Add accounts → Click switch → Codex uses new account）
- [x] 5.2 配步骤截图或图标

## 6. Install 区域

- [x] 6.1 Homebrew 安装命令（带复制按钮）
- [x] 6.2 DMG 直接下载链接
- [x] 6.3 系统要求说明（macOS 14+）

## 7. FAQ 区域

- [x] 7.1 编写 5-8 个常见问题（免费？凭证安全？支持 Teams？数据存哪？）
- [x] 7.2 手风琴展开交互

## 8. Footer

- [x] 8.1 版权信息 + GitHub 链接 + License

## 9. 双语支持

- [x] 9.1 所有文案区域添加 `data-lang="en"` / `data-lang="zh"` 标签
- [x] 9.2 导航栏语言切换按钮
- [x] 9.3 `localStorage` 记住语言偏好

## 10. 部署与验证

- [ ] 10.1 GitHub Pages 配置（Settings → Pages → Source: /docs）
- [ ] 10.2 自定义域名配置（可选）
- [x] 10.3 移动端响应式验证
- [ ] 10.4 Lighthouse 性能检测（目标: Performance > 95）
- [ ] 10.5 Open Graph 预览验证（Twitter Card / Facebook debugger）
