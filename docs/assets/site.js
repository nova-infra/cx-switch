const translations = {
  zh: {
    navStory: "提炼",
    navFeatures: "功能",
    navInstall: "安装",
    navPublish: "发布",
    langLabel: "中文 / EN",
    heroEyebrow: "官方网站",
    heroTitle: "CX Switch",
    heroLead:
      "一个菜单栏账户切换助手，兼顾清晰层级、沉稳视觉和中英双语体验。",
    ctaPrimary: "查看安装方式",
    ctaSecondary: "阅读 GPT-5.4 文章",
    heroNote:
      "这个页面也遵循它总结的思路：一条故事线、一个视觉锚点、少量但有效的动效。",
    mockCurrent: "当前账户",
    mockPlan: "Plus 计划",
    mockPrimary: "5 小时窗口",
    mockSecondary: "周窗口",
    mockAdd: "添加账户",
    mockRefresh: "刷新",
    mockImport: "导入 Token",
    storyKicker: "GPT-5.4 的启发",
    storyTitle: "先定故事，再定视觉。",
    storyLead:
      "OpenAI 那篇文章强调，真正出色的前端来自更好的约束、更清楚的内容和可验证的设计。这个页面把这些建议直接变成了结构。",
    principle1Title: "先定义约束",
    principle1Body:
      "先确定布局、配色、层级和语气，再往里填细节。模型看到规则越早，结果越稳定。",
    principle2Title: "用叙事组织页面",
    principle2Body:
      "首屏、支持信息、细节补充、最终行动。这样的节奏能让页面集中，不会变成泛化的仪表盘。",
    principle3Title: "基于真实内容",
    principle3Body:
      "真实的产品文案、真实的状态和真实的安装步骤，会让页面比纯装饰更可信。",
    principle4Title: "桌面和移动端都要验证",
    principle4Body:
      "文章反复强调检查与迭代。这个页面使用响应式首屏、可读间距，以及尊重减少动态效果的动效策略。",
    featuresKicker: "当前功能",
    featuresTitle: "这是仓库里已经具备的能力。",
    featuresLead:
      "这些内容来自当前的 SwiftUI 重写代码，所以官网和实际产品保持一致。",
    feature1Title: "菜单栏优先",
    feature1Body:
      "CX Switch 作为 macOS 菜单栏应用运行，没有 Dock 图标，切换账户时更轻量。",
    feature2Title: "用量一眼可见",
    feature2Body:
      "当前账户、计划标识、5 小时用量、周用量和重置倒计时，都集中在一个面板里。",
    feature3Title: "快速账户操作",
    feature3Body: "添加、保存、切换、刷新和导入 refresh token 都可以在菜单栏内完成。",
    feature4Title: "中英双语就绪",
    feature4Body:
      "UI 文案已经集中管理，可按中文或英文显示，便于维护和后续本地化。",
    installKicker: "安装",
    installTitle: "几步就能在本地跑起来。",
    installLead:
      "这个仓库同时提供 Swift Package 和 Xcode 项目，所以本地启动路径很直接。",
    installStep1Title: "打开项目",
    installStep1Body:
      "使用 macOS 14+ 和 Xcode 15+，然后打开 `CXSwitch.xcodeproj`。",
    installStep2Title: "运行应用",
    installStep2Body:
      "启动 `CXSwitch` 后，它会出现在菜单栏里，并自动加载仪表盘和账户数据。",
    installStep3Title: "开始管理账户",
    installStep3Body:
      "从菜单栏面板里添加账户、导入 refresh token，或者切换到已保存的账户。",
    publishKicker: "GitHub Pages",
    publishTitle: "已经准备好自动发布。",
    publishLead:
      "这个站点放在 `docs/` 下，并配有 GitHub Actions workflow，推送后会自动发布到 GitHub Pages。",
    publishLabel: "部署路径",
    publishLabel2: "你会得到",
    publishResult: "一个易维护的中英双语官网。",
    footerCopy: "基于 GPT-5.4 前端文章提炼，并为 CX Switch 做了落地改写。",
  },
  en: {
    navStory: "Summary",
    navFeatures: "Features",
    navInstall: "Install",
    navPublish: "Deploy",
    langLabel: "EN / 中文",
    heroEyebrow: "Official website",
    heroTitle: "CX Switch",
    heroLead:
      "A menu bar companion for switching OpenAI accounts with clear hierarchy, calm visuals, and bilingual polish.",
    ctaPrimary: "See the install steps",
    ctaSecondary: "Read the GPT-5.4 article",
    heroNote:
      "This page follows the same guidance it summarizes: one story, one visual anchor, and motion that actually earns its place.",
    mockCurrent: "Current account",
    mockPlan: "Plus plan",
    mockPrimary: "5 hour window",
    mockSecondary: "Weekly window",
    mockAdd: "Add account",
    mockRefresh: "Refresh",
    mockImport: "Import token",
    storyKicker: "What GPT-5.4 teaches us",
    storyTitle: "Design starts with a story, not with chrome.",
    storyLead:
      "The OpenAI article argues that better frontends come from better constraints, clearer content, and visual verification. This page turns that advice into structure.",
    principle1Title: "Define constraints first",
    principle1Body:
      "Pick the layout, palette, hierarchy, and tone before adding details. Clear rules lead to more reliable outputs.",
    principle2Title: "Use a narrative page flow",
    principle2Body:
      "Hero, support, detail, and final action. That rhythm keeps the page focused instead of drifting into dashboard sprawl.",
    principle3Title: "Ground the page in real content",
    principle3Body:
      "Real product copy, real states, and real install steps make the site feel credible instead of decorative.",
    principle4Title: "Verify on desktop and mobile",
    principle4Body:
      "The article leans on inspection and iteration. This page uses responsive layout, readable spacing, and reduced-motion friendly animation.",
    featuresKicker: "Current features",
    featuresTitle: "Everything the current app already does.",
    featuresLead:
      "These details come from the SwiftUI rewrite in this repository, so the website stays aligned with the product.",
    feature1Title: "Menu bar first",
    feature1Body:
      "CX Switch runs as a macOS menu bar app with no Dock icon, keeping account switching close at hand.",
    feature2Title: "Usage at a glance",
    feature2Body:
      "The app shows your current account, plan badge, 5-hour usage, weekly usage, and reset countdowns in one compact panel.",
    feature3Title: "Fast account actions",
    feature3Body:
      "Add, save, switch, refresh, and import refresh tokens without leaving the menu bar.",
    feature4Title: "Bilingual ready",
    feature4Body:
      "UI strings are centralized and can be shown in Chinese or English, which makes localization easier to maintain.",
    installKicker: "Install",
    installTitle: "Run it locally in a few steps.",
    installLead:
      "The repository ships as both a Swift package and an Xcode project, so local setup stays straightforward.",
    installStep1Title: "Open the project",
    installStep1Body:
      "Use macOS 14+ and Xcode 15+, then open `CXSwitch.xcodeproj`.",
    installStep2Title: "Run the app",
    installStep2Body:
      "Launch `CXSwitch` and let it appear in the menu bar. It loads the dashboard and account data automatically.",
    installStep3Title: "Start managing accounts",
    installStep3Body:
      "From the menu bar panel, add an account, import a refresh token, or switch to a saved account.",
    publishKicker: "GitHub Pages",
    publishTitle: "Ready for automatic deployment.",
    publishLead:
      "The site lives in `docs/` and ships with a GitHub Actions workflow that publishes it to GitHub Pages on every push.",
    publishLabel: "Deployment path",
    publishLabel2: "What you get",
    publishResult: "A bilingual marketing site that stays easy to maintain.",
    footerCopy: "Distilled from the GPT-5.4 frontend article and adapted for CX Switch.",
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
