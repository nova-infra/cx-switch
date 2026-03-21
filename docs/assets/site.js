const translations = {
  zh: {
    navFeatures: "功能",
    navDownload: "下载",
    langLabel: "中文 / EN",
    heroEyebrow: "官方网站",
    heroTitle: "CX Switch",
    heroLead:
      "快速切换 OpenAI 账户，一眼看到用量，让当前工作区始终在手边。",
    ctaPrimary: "立即下载",
    ctaSecondary: "查看功能",
    heroNote: "一页讲清楚产品价值、核心功能和下载入口。",
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
    featuresKicker: "功能",
    featuresTitle: "专为快速切换账户而设计。",
    featuresLead: "CX Switch 把常用动作收拢到一个简洁的菜单栏面板里。",
    feature1Title: "纯菜单栏",
    feature1Body: "应用驻留在 macOS 菜单栏，不占 Dock。",
    feature2Title: "当前与已保存账户",
    feature2Body: "在当前账户和已保存账户之间快速切换。",
    feature3Title: "用量一眼可见",
    feature3Body: "直接查看用量条和重置时间，不用打开别的页面。",
    feature4Title: "快速账户操作",
    feature4Body: "添加账户、刷新用量、导入 token 都很快。",
    downloadKicker: "下载",
    downloadTitle: "获取应用。",
    downloadLead: "下载最新版本，几分钟内开始使用 CX Switch。",
    downloadLabel: "最新版本",
    downloadLabel2: "平台",
    downloadBuild: "最新版本",
    downloadPlatform: "macOS",
    downloadCtaPrimary: "立即下载",
    downloadCtaSecondary: "查看功能",
  },
  en: {
    navFeatures: "Features",
    navDownload: "Download",
    langLabel: "EN / 中文",
    heroEyebrow: "Official website",
    heroTitle: "CX Switch",
    heroLead:
      "Switch OpenAI accounts quickly, see usage at a glance, and keep the current workspace close at hand.",
    ctaPrimary: "Download now",
    ctaSecondary: "See features",
    heroNote: "One page that explains the product value, core features, and download path.",
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
    featuresKicker: "Features",
    featuresTitle: "Designed for fast account switching.",
    featuresLead:
      "CX Switch keeps the most common actions inside a clean menu bar panel.",
    feature1Title: "Menu bar first",
    feature1Body: "The app lives in the macOS menu bar and stays out of the Dock.",
    feature2Title: "Current and saved accounts",
    feature2Body:
      "Move quickly between your current account and saved accounts.",
    feature3Title: "Usage at a glance",
    feature3Body:
      "Check usage bars and reset timing without leaving the panel.",
    feature4Title: "Fast account actions",
    feature4Body:
      "Add accounts, refresh usage, and import tokens in a few clicks.",
    downloadKicker: "Download",
    downloadTitle: "Get the app.",
    downloadLead: "Download the latest version and start using CX Switch in minutes.",
    downloadLabel: "Latest version",
    downloadLabel2: "Platform",
    downloadBuild: "Latest version",
    downloadPlatform: "macOS",
    downloadCtaPrimary: "Download now",
    downloadCtaSecondary: "See features",
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
