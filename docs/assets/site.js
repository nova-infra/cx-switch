const translations = {
  zh: {
    navMethod: "方法",
    navProduct: "产品",
    navInstall: "安装",
    navDownload: "下载",
    langLabel: "中文 / EN",
    heroEyebrow: "官方网站",
    heroTitle: "CX Switch",
    heroLead:
      "一个菜单栏应用，用来切换 OpenAI 账户、查看用量，并把当前工作区放在最顺手的位置。",
    ctaPrimary: "阅读方法",
    ctaSecondary: "查看产品事实",
    heroNote:
      "这个页面是从仓库本身写出来的：先看文件，再写主张，最后做润色。",
    mockEyebrow: "菜单栏面板",
    mockBadge: "在线",
    mockCurrent: "当前账户",
    mockPlan: "Plus 计划",
    mockPrimary: "5 小时窗口",
    mockPrimaryTime: "剩余 47 分钟",
    mockSecondary: "周窗口",
    mockSecondaryTime: "剩余 2 天",
    mockAdd: "添加账户",
    mockRefresh: "刷新",
    mockImport: "导入 Token",
    methodKicker: "方法",
    methodTitle: "把仓库当作唯一来源。",
    methodLead:
      "这个官网和 skill 用的是同一套思路：先读代码，提炼事实，组织叙事，再逐条验证。",
    principle1Title: "先读源码",
    principle1Body:
      "从入口、视图、服务和配置开始，确保官网描述的是产品真实能力。",
    principle2Title: "提炼产品事实",
    principle2Body:
      "只保留仓库能证明的内容：当前账户、已保存账户、用量条、Token 导入和语言支持。",
    principle3Title: "组织短叙事",
    principle3Body:
      "先讲价值，再给证据，然后说明安装和下载。每个区块只做一件事。",
    principle4Title: "逐条核对",
    principle4Body:
      "发布前检查每一句文案是否都能回到代码，并确认桌面和移动端都能正常阅读。",
    productKicker: "产品",
    productTitle: "一个轻量的 OpenAI 账户切换工具。",
    productLead:
      "当前应用是一个 macOS 菜单栏工具，这些功能都能在代码库中直接看到。",
    feature1Title: "纯菜单栏",
    feature1Body:
      "CX Switch 作为 macOS 菜单栏应用运行，没有 Dock 图标。",
    feature2Title: "当前与已保存账户",
    feature2Body:
      "面板会显示当前账户和已保存账户列表，方便快速切换。",
    feature3Title: "用量与重置时间",
    feature3Body:
      "当前账户卡片会在数据可用时显示用量条和重置倒计时。",
    feature4Title: "导入与双语支持",
    feature4Body:
      "用户可以导入 refresh token、打开设置或状态，并在中英文之间切换 UI。",
    installKicker: "安装",
    installTitle: "在本地运行应用。",
    installLead:
      "项目是一个基于 Swift Package 的 Xcode 应用，在 macOS 14+ 上就能直接启动。",
    installStep1Title: "打开项目",
    installStep1Body:
      "在 macOS 14+ 和 Xcode 15+ 中打开 `CXSwitch.xcodeproj`。",
    installStep2Title: "运行应用",
    installStep2Body:
      "启动 `CXSwitch` 后，它会出现在菜单栏里，并自动加载仪表盘和账户数据。",
    installStep3Title: "使用面板",
    installStep3Body:
      "在菜单栏面板里添加账户、切换账户、刷新用量或导入 refresh token。",
    downloadKicker: "下载",
    downloadTitle: "获取应用。",
    downloadLead:
      "这里放当前构建、最新发布版本和源码仓库的入口。",
    downloadLabel: "最新构建",
    downloadLabel2: "源码",
    downloadBuild: "GitHub Releases",
    downloadSource: "github.com/nova-infra/cx-switch",
    downloadCtaPrimary: "打开发布页",
    downloadCtaSecondary: "查看源码",
    footerCopy:
      "基于源码事实、repo-site-builder 方法和双语官方站点结构整理而成。",
  },
  en: {
    navMethod: "Method",
    navProduct: "Product",
    navInstall: "Install",
    navDownload: "Download",
    langLabel: "EN / 中文",
    heroEyebrow: "Official website",
    heroTitle: "CX Switch",
    heroLead:
      "A menu bar app for switching OpenAI accounts, checking usage, and keeping the current workspace close at hand.",
    ctaPrimary: "Read the method",
    ctaSecondary: "See product facts",
    heroNote:
      "This page is written from the repository itself: files first, claims second, polish third.",
    mockEyebrow: "Menu bar panel",
    mockBadge: "Live",
    mockCurrent: "Current account",
    mockPlan: "Plus plan",
    mockPrimary: "5 hour window",
    mockPrimaryTime: "47 min left",
    mockSecondary: "Weekly window",
    mockSecondaryTime: "2 days left",
    mockAdd: "Add account",
    mockRefresh: "Refresh",
    mockImport: "Import token",
    methodKicker: "Method",
    methodTitle: "Treat the repo as the source of truth.",
    methodLead:
      "The website and the skill use the same process: read the code, extract facts, shape a short narrative, and verify each claim.",
    principle1Title: "Read the source",
    principle1Body:
      "Start with entry points, views, services, and config so the site reflects what the product actually does.",
    principle2Title: "Extract product facts",
    principle2Body:
      "Keep only what the repository can prove: current account, saved accounts, usage bars, token import, and language support.",
    principle3Title: "Shape a short narrative",
    principle3Body:
      "Lead with the promise, then show proof, then explain install and download. One job per section.",
    principle4Title: "Verify against the repo",
    principle4Body:
      "Before shipping, check every line of copy against the code and confirm the page reads well on desktop and mobile.",
    productKicker: "Product",
    productTitle: "A compact tool for OpenAI account switching.",
    productLead:
      "The current app is a macOS menu bar utility, and these are the capabilities visible in the codebase today.",
    feature1Title: "Menu bar only",
    feature1Body:
      "CX Switch runs as a macOS menu bar app with no Dock icon.",
    feature2Title: "Current and saved accounts",
    feature2Body:
      "The panel shows the current account and a saved-account list for quick switching.",
    feature3Title: "Usage and reset timers",
    feature3Body:
      "The current account card shows usage bars and reset countdowns when data is available.",
    feature4Title: "Import and bilingual support",
    feature4Body:
      "Users can import a refresh token, open settings or status, and switch the UI between Chinese and English.",
    installKicker: "Install",
    installTitle: "Run the app locally.",
    installLead:
      "The project is an Xcode app built from a Swift package, so setup is straightforward on macOS 14+.",
    installStep1Title: "Open the project",
    installStep1Body:
      "Use macOS 14+ and Xcode 15+, then open `CXSwitch.xcodeproj`.",
    installStep2Title: "Run the app",
    installStep2Body:
      "Launch `CXSwitch` and let it appear in the menu bar. The app loads your dashboard and account data automatically.",
    installStep3Title: "Use the panel",
    installStep3Body:
      "Add accounts, switch between them, refresh usage, or import a refresh token from the menu bar panel.",
    downloadKicker: "Download",
    downloadTitle: "Get the app.",
    downloadLead:
      "This area holds the current build, the latest releases, and the source repository.",
    downloadLabel: "Latest build",
    downloadLabel2: "Source",
    downloadBuild: "GitHub Releases",
    downloadSource: "github.com/nova-infra/cx-switch",
    downloadCtaPrimary: "Open releases",
    downloadCtaSecondary: "View source",
    footerCopy:
      "Assembled from source truth, the repo-site-builder method, and a bilingual official-site structure.",
  },
};

const root = document.documentElement;
const toggle = document.getElementById("langToggle");
const copyNodes = document.querySelectorAll("[data-i18n]");

function getStoredLanguage() {
  try {
    return localStorage.getItem("cx-switch-language");
  } catch {
    return null;
  }
}

function setStoredLanguage(lang) {
  try {
    localStorage.setItem("cx-switch-language", lang);
  } catch {
    // Ignore storage failures in restricted or file:// contexts.
  }
}

function applyLanguage(lang) {
  const dictionary = translations[lang] || translations.zh;
  root.lang = lang === "en" ? "en" : "zh-Hans";
  root.dataset.lang = lang;
  toggle.setAttribute("aria-pressed", String(lang === "en"));

  for (const node of copyNodes) {
    const key = node.dataset.i18n;
    if (dictionary[key]) {
      node.textContent = dictionary[key];
    }
  }

  setStoredLanguage(lang);
}

const savedLanguage = getStoredLanguage();
const prefersEnglish = navigator.language.toLowerCase().startsWith("en");
const initialLanguage = savedLanguage || (prefersEnglish ? "en" : "zh");

applyLanguage(initialLanguage);

toggle.addEventListener("click", () => {
  const nextLanguage = root.dataset.lang === "en" ? "zh" : "en";
  applyLanguage(nextLanguage);
});
