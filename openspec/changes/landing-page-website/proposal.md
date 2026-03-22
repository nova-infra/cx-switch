## Why

CX Switch 是私有仓库，没有公开的产品页面。用户无法通过搜索引擎发现它，也无法在分享链接时提供一个专业的落地页。一个轻量级官网可以：

- 作为产品的公开门面，建立专业形象
- 提供下载入口（DMG / Homebrew Cask）
- 作为社交媒体、论坛、Product Hunt 等推广渠道的着陆页
- 展示功能截图和使用场景，降低理解成本

## What Changes

- 新建独立仓库 `cx-switch-site`（或在当前仓库的 `docs/` 目录下）
- 单页面落地站（Single Page），使用 HTML + Tailwind CSS，无构建工具依赖
- 部署到 GitHub Pages / Cloudflare Pages / Vercel
- 内容包含：Hero 区域、功能亮点、截图展示、下载入口、FAQ

## Impact

- 不影响 CX Switch 主程序代码
- 新增独立前端项目（~5 个文件）
- 需要准备产品截图和图标素材
