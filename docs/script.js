(function () {
  const STORAGE_KEY = "cx-switch-site-lang";
  const root = document.documentElement;

  function getStoredLanguage() {
    try {
      return localStorage.getItem(STORAGE_KEY);
    } catch {
      return null;
    }
  }

  function setStoredLanguage(lang) {
    try {
      localStorage.setItem(STORAGE_KEY, lang);
    } catch {
      // file:// 或受限环境
    }
  }

  function applyLanguage(lang) {
    const resolved = lang === "zh" ? "zh" : "en";
    root.lang = resolved === "en" ? "en" : "zh-Hans";
    root.dataset.lang = resolved;

    const toggle = document.getElementById("langToggle");
    if (toggle) {
      toggle.setAttribute("aria-pressed", String(resolved === "zh"));
      toggle.setAttribute(
        "aria-label",
        resolved === "en" ? "Switch to Chinese" : "Switch to English"
      );
    }

    for (const el of document.querySelectorAll("[data-lang]")) {
      const key = el.getAttribute("data-lang");
      if (key !== "en" && key !== "zh") continue;
      el.toggleAttribute("hidden", key !== resolved);
    }

    setStoredLanguage(resolved);
  }

  const saved = getStoredLanguage();
  applyLanguage(saved || "en");

  const toggle = document.getElementById("langToggle");
  if (toggle) {
    toggle.addEventListener("click", () => {
      const next = root.dataset.lang === "zh" ? "en" : "zh";
      applyLanguage(next);
    });
  }

  for (const copyBtn of document.querySelectorAll("[data-copy]")) {
    copyBtn.addEventListener("click", async () => {
      const cmd = copyBtn.getAttribute("data-copy") || "";
      try {
        await navigator.clipboard.writeText(cmd);
        copyBtn.classList.add("ring-2", "ring-[#007AFF]/50");
        const visible = copyBtn.querySelector("[data-lang]:not([hidden])");
        const prev = visible ? visible.textContent : copyBtn.textContent;
        const done =
          root.dataset.lang === "zh"
            ? copyBtn.getAttribute("data-copied-zh") || "已复制"
            : copyBtn.getAttribute("data-copied-en") || "Copied";
        if (visible) visible.textContent = done;
        window.setTimeout(() => {
          if (visible) visible.textContent = prev;
          copyBtn.classList.remove("ring-2", "ring-[#007AFF]/50");
        }, 1600);
      } catch {
        copyBtn.classList.add("animate-pulse");
        window.setTimeout(() => copyBtn.classList.remove("animate-pulse"), 600);
      }
    });
  }

  const reduceMotion =
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (!reduceMotion && "IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("is-visible");
          io.unobserve(entry.target);
        }
      },
      { root: null, threshold: 0.12, rootMargin: "0px 0px -6% 0px" }
    );

    for (const el of document.querySelectorAll(".reveal")) {
      io.observe(el);
    }
  } else {
    for (const el of document.querySelectorAll(".reveal")) {
      el.classList.add("is-visible");
    }
  }
})();
