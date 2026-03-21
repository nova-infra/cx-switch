import Electrobun, {
  ApplicationMenu,
  BrowserView,
  BrowserWindow,
  Screen,
  Tray,
  Utils,
  type MenuItemConfig,
} from "electrobun/bun";
import {
  APP_NAME,
  type AccountIdentity,
  type AccountRegistryEntry,
  type AppRPC,
  type DashboardState,
  type LoginFlowState,
  type PlanType,
} from "../shared/rpc";
import {
  deleteRegistryEntry,
  deriveAccountIdentity,
  findMatchingAccount,
  getDataFolder,
  importRefreshToken as exchangeRefreshToken,
  loadKeychainAuth,
  loadPreferences,
  loadRegistry,
  maskEmail,
  normalizePlanType,
  readCurrentAuthBlob,
  saveRegistry,
  savePreferences,
  sortRegistryByLastUsed,
  sanitizeRefreshTokenInput,
  updateRegistryEntry,
  upsertAccountRegistryEntry,
  withAccountSnapshot,
  writeCurrentAuthBlob,
} from "./accountStore";
import { CodexAppServerClient } from "./codexAppServer";
import { normalizeUsageSnapshot, probeUsageSnapshot, selectRateLimitSnapshot } from "./usage";

const devServerUrl = process.env.ELECTROBUN_VITE_DEV_SERVER_URL;
const appUrl = devServerUrl ?? "views://app/index.html";

const USE_TRAY_MENU = true;

const POPUP_WIDTH = 404;
const POPUP_HEIGHT = 540;
const POPUP_MARGIN = 10;
const HIDDEN_X = -20_000;
const HIDDEN_Y = -20_000;
const SAVED_ACCOUNT_STALE_MS = 60_000;
const SAVED_ACCOUNT_PROBE_TIMEOUT_MS = 15_000;
const SAVED_ACCOUNT_PROBE_CONCURRENCY = 2;
const LOGIN_COMPLETION_TIMEOUT_MS = 10 * 60 * 1000;
const STATUS_PAGE_URL = "https://status.openai.com/";
let popupOpenedAt = 0;

type AccountReadResponse = {
  account:
    | {
        type: "chatgpt";
        email: string;
        planType: PlanType | string;
      }
    | {
        type: "apiKey";
      }
    | null;
  requiresOpenaiAuth: boolean;
};

type RateLimitsResponse = {
  rateLimits: {
    limitId?: string | null;
    planType?: PlanType | null;
    primary?: {
      usedPercent: number;
      resetsAt?: number | null;
      windowDurationMins?: number | null;
    } | null;
    secondary?: {
      usedPercent: number;
      resetsAt?: number | null;
      windowDurationMins?: number | null;
    } | null;
    credits?: {
      hasCredits: boolean;
      unlimited: boolean;
      balance: string | null;
    } | null;
  } | null;
  rateLimitsByLimitId?: Record<string, RateLimitsResponse["rateLimits"]> | null;
};

type LoginStartResponse =
  | {
      type: "chatgpt";
      loginId: string;
      authUrl: string;
    }
  | {
      type: "apiKey";
    }
  | {
      type: "chatgptAuthTokens";
    };

type LoginCompletedNotification = {
  loginId: string | null;
  success: boolean;
  error: string | null;
};

const rpc = BrowserView.defineRPC<AppRPC>({
  handlers: {
    requests: {
      getDashboardState: () => controller.getDashboardState(),
      refreshCurrentAccount: () => controller.refreshCurrentAccount(),
      refreshSavedAccounts: () => controller.refreshSavedAccounts(true),
      saveCurrentAccount: () => controller.saveCurrentAccount(),
      importRefreshToken: ({ refreshToken }) => controller.importRefreshToken(refreshToken ?? ""),
      readClipboardText: () => Utils.clipboardReadText() ?? "",
      startAddAccount: () => controller.startAddAccount(),
      cancelAddAccount: ({ loginId }) => controller.cancelAddAccount(loginId ?? null),
      switchAccount: (identity) => controller.switchAccount(identity),
      removeAccount: (identity) => controller.removeAccount(identity),
      setMaskEmails: ({ maskEmails }) => controller.setMaskEmails(maskEmails),
      openStatusPage: () => controller.openStatusPage(),
      openSettings: () => controller.openSettings(),
      quitApp: () => controller.quitApp(),
    },
    messages: {},
  },
});

class DashboardController {
  private readonly appServer = new CodexAppServerClient();
  private loginFlow: LoginFlowState = this.createLoginFlow();
  private statusMessage: string | null = null;
  private errorMessage: string | null = null;
  private noticeMessage: string | null = null;
  private refreshing = false;
  private popupVisible = false;
  private cliVersionPromise: Promise<string> | null = null;

  setPopupVisible(visible: boolean): void {
    this.popupVisible = visible;
  }

  isPopupVisible(): boolean {
    return this.popupVisible;
  }

  async getDashboardState(): Promise<DashboardState> {
    this.compactEphemeralState();

    const [preferences, savedAccounts, currentAccount] = await Promise.all([
      loadPreferences(),
      sortRegistryByLastUsed(),
      this.readCurrentAccount(),
    ]);

    return {
      appName: APP_NAME,
      loading: false,
      refreshing: this.refreshing,
      updatedAt: new Date().toISOString(),
      currentAccount,
      savedAccounts,
      preferences,
      loginFlow: {
        ...this.loginFlow,
        active:
          this.loginFlow.active ||
          this.loginFlow.status === "starting" ||
          this.loginFlow.status === "waiting",
      },
      status: this.statusMessage,
      error: this.errorMessage,
      notice: this.noticeMessage,
    };
  }

  async refreshCurrentAccount(): Promise<DashboardState> {
    this.errorMessage = null;
    this.statusMessage = "Current account refreshed.";
    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  async refreshSavedAccounts(force: boolean): Promise<DashboardState> {
    const accounts = await loadRegistry();
    if (accounts.length === 0) {
      const state = await this.getDashboardState();
      await this.broadcastState(state);
      return state;
    }

    const cliVersion = await this.getCodexCliVersion();
    const targets = accounts.filter((account) => force || this.isSnapshotStale(account));
    if (targets.length === 0) {
      const state = await this.getDashboardState();
      await this.broadcastState(state);
      return state;
    }

    this.refreshing = true;
    this.errorMessage = null;
    await this.broadcastState();

    const updates = new Map<string, AccountRegistryEntry>();
    try {
      await mapWithConcurrency(
        targets,
        SAVED_ACCOUNT_PROBE_CONCURRENCY,
        async (account) => {
          const auth = loadKeychainAuth(account.id);
          if (!auth) {
            updates.set(
              account.id,
              withAccountSnapshot(
                account,
                account.usageSnapshot,
                "Missing saved credentials in Keychain.",
              ),
            );
            return;
          }

          try {
            const usageSnapshot = await probeUsageSnapshot({
              auth,
              planType: account.planType,
              cliVersion,
              timeoutMs: SAVED_ACCOUNT_PROBE_TIMEOUT_MS,
            });

            updates.set(
              account.id,
              withAccountSnapshot(
                {
                  ...account,
                  planType: usageSnapshot?.planType ?? account.planType,
                },
                usageSnapshot,
                null,
              ),
            );
          } catch (error) {
            updates.set(
              account.id,
              withAccountSnapshot(
                account,
                account.usageSnapshot,
                error instanceof Error ? error.message : "Failed to refresh usage.",
              ),
            );
          }
        },
      );

      if (updates.size > 0) {
        await saveRegistry(
          accounts.map((account) => updates.get(account.id) ?? account),
        );
      }

      this.statusMessage =
        updates.size > 0 ? "Saved account usage refreshed." : this.statusMessage;
      this.noticeMessage = null;
    } catch (error) {
      this.errorMessage =
        error instanceof Error ? error.message : "Failed to refresh saved accounts.";
    } finally {
      this.refreshing = false;
    }

    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  async saveCurrentAccount(): Promise<DashboardState> {
    const currentAccount = await this.readCurrentAccount();
    const auth = await readCurrentAuthBlob();

    if (!currentAccount?.email || !auth) {
      throw new Error("No active ChatGPT account is available to save.");
    }

    await upsertAccountRegistryEntry({
      auth,
      email: currentAccount.email,
      planType: currentAccount.planType,
      chatgptAccountId: currentAccount.chatgptAccountId,
      usageSnapshot: currentAccount.usageSnapshot,
    });

    this.statusMessage = "Current account saved.";
    this.errorMessage = null;

    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  async importRefreshToken(refreshToken: string): Promise<DashboardState> {
    const sanitized = sanitizeRefreshTokenInput(refreshToken);
    if (!sanitized) {
      throw new Error("Refresh token is required.");
    }

    this.statusMessage = "Importing account from refresh token...";
    this.errorMessage = null;
    this.noticeMessage = null;
    await this.broadcastState();

    try {
      const imported = await exchangeRefreshToken(sanitized);
      await writeCurrentAuthBlob(imported.auth);
      await this.appServer.restart();

      const currentAccount = await this.readCurrentAccount();
      if (!currentAccount?.email) {
        throw new Error("Imported refresh token was accepted, but Codex could not read the account.");
      }

      await upsertAccountRegistryEntry({
        auth: imported.auth,
        email: currentAccount.email,
        planType: currentAccount.planType ?? imported.planType,
        chatgptAccountId: currentAccount.chatgptAccountId ?? imported.identity.chatgptAccountId,
        usageSnapshot: currentAccount.usageSnapshot,
      });

      this.statusMessage = "Refresh token imported and switched.";
      this.errorMessage = null;
      const state = await this.getDashboardState();
      await this.broadcastState(state);
      return state;
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to import refresh token.";
      this.statusMessage = null;
      this.errorMessage = message;
      const state = await this.getDashboardState();
      await this.broadcastState(state);
      throw error instanceof Error ? error : new Error(message);
    }
  }

  async startAddAccount(): Promise<DashboardState> {
    this.loginFlow = {
      active: true,
      loginId: null,
      authUrl: null,
      status: "starting",
      message: "Preparing the ChatGPT sign-in flow...",
      error: null,
      startedAt: new Date().toISOString(),
      completedAt: null,
    };
    this.errorMessage = null;
    await this.broadcastState();

    try {
      const response = (await this.appServer.request(
        "account/login/start",
        { type: "chatgpt" },
        20_000,
      )) as LoginStartResponse;

      if (response.type !== "chatgpt" || !response.loginId || !response.authUrl) {
        throw new Error("Unexpected login response from Codex.");
      }

      this.loginFlow = {
        active: true,
        loginId: response.loginId,
        authUrl: response.authUrl,
        status: "waiting",
        message: "Complete the ChatGPT sign-in in your browser.",
        error: null,
        startedAt: this.loginFlow.startedAt ?? new Date().toISOString(),
        completedAt: null,
      };

      Utils.openExternal(response.authUrl);
      await this.broadcastState();

      void this.appServer
        .waitForNotification<LoginCompletedNotification>(
          "account/login/completed",
          (params) =>
            (params as LoginCompletedNotification | null)?.loginId === response.loginId,
          LOGIN_COMPLETION_TIMEOUT_MS,
        )
        .then(async (result) => {
          await this.finishLogin(result);
        })
        .catch(async (error) => {
          if (this.loginFlow.loginId !== response.loginId) {
            return;
          }

          this.loginFlow = {
            ...this.loginFlow,
            active: false,
            loginId: null,
            authUrl: null,
            status: "error",
            message: null,
            error:
              error instanceof Error ? error.message : "Login flow timed out.",
            completedAt: new Date().toISOString(),
          };
          this.errorMessage = this.loginFlow.error;
          await this.broadcastState();
        });

      return this.getDashboardState();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to start account login.";
      this.loginFlow = {
        active: false,
        loginId: null,
        authUrl: null,
        status: "error",
        message: null,
        error: message,
        startedAt: this.loginFlow.startedAt,
        completedAt: new Date().toISOString(),
      };
      this.errorMessage = message;

      const state = await this.getDashboardState();
      await this.broadcastState(state);
      return state;
    }
  }

  async cancelAddAccount(loginId: string | null): Promise<DashboardState> {
    const activeLoginId = loginId ?? this.loginFlow.loginId;
    if (activeLoginId) {
      await this.appServer.request("account/login/cancel", { loginId: activeLoginId });
    }

    this.loginFlow = {
      active: false,
      loginId: null,
      authUrl: null,
      status: "canceled",
      message: null,
      error: null,
      startedAt: this.loginFlow.startedAt,
      completedAt: new Date().toISOString(),
    };
    this.statusMessage = "Login flow canceled.";
    this.errorMessage = null;

    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  async switchAccount(identity: AccountIdentity): Promise<DashboardState> {
    const savedAccount = await this.resolveSavedAccount(identity);
    if (!savedAccount) {
      throw new Error("Saved account not found.");
    }

    const auth = loadKeychainAuth(savedAccount.id);
    if (!auth) {
      throw new Error("Saved account credentials are missing from Keychain.");
    }

    await writeCurrentAuthBlob(auth);
    await updateRegistryEntry(savedAccount.id, (entry) => ({
      ...entry,
      lastUsedAt: new Date().toISOString(),
      usageError: null,
    }));
    await this.appServer.restart();

    this.statusMessage = `Switched to ${savedAccount.email}.`;
    this.errorMessage = null;

    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  async removeAccount(identity: AccountIdentity): Promise<DashboardState> {
    const savedAccount = await this.resolveSavedAccount(identity);
    if (!savedAccount) {
      throw new Error("Saved account not found.");
    }

    await deleteRegistryEntry(savedAccount.id);
    this.statusMessage = `Removed ${savedAccount.email}.`;
    this.errorMessage = null;

    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  async setMaskEmails(maskEmails: boolean): Promise<DashboardState> {
    await savePreferences({ maskEmails });
    this.statusMessage = maskEmails ? "Email masking enabled." : "Email masking disabled.";
    this.errorMessage = null;

    const state = await this.getDashboardState();
    await this.broadcastState(state);
    return state;
  }

  openStatusPage(): boolean {
    return Utils.openExternal(STATUS_PAGE_URL);
  }

  openSettings(): boolean {
    return Utils.openPath(getDataFolder());
  }

  async quitApp(): Promise<boolean> {
    await this.shutdown();
    queueMicrotask(() => {
      Utils.quit();
    });
    return true;
  }

  async handlePopupOpened(): Promise<void> {
    await this.broadcastState();
    try {
      await this.refreshSavedAccounts(false);
    } catch {
      // Ignore background refresh errors here; they are surfaced via state.
    }
  }

  async shutdown(): Promise<void> {
    await this.appServer.shutdown();
  }

  private async finishLogin(result: LoginCompletedNotification): Promise<void> {
    if (this.loginFlow.loginId !== result.loginId) {
      return;
    }

    if (!result.success) {
      this.loginFlow = {
        active: false,
        loginId: null,
        authUrl: null,
        status: result.error ? "error" : "canceled",
        message: null,
        error: result.error,
        startedAt: this.loginFlow.startedAt,
        completedAt: new Date().toISOString(),
      };
      this.errorMessage = result.error;
      this.statusMessage = result.error ? null : "Login flow canceled.";
      await this.broadcastState();
      return;
    }

    try {
      const currentAccount = await this.readCurrentAccount();
      const auth = await readCurrentAuthBlob();
      if (!currentAccount?.email || !auth) {
        throw new Error("Login completed, but current account data is unavailable.");
      }

      await upsertAccountRegistryEntry({
        auth,
        email: currentAccount.email,
        planType: currentAccount.planType,
        chatgptAccountId: currentAccount.chatgptAccountId,
        usageSnapshot: currentAccount.usageSnapshot,
      });

      this.loginFlow = {
        active: false,
        loginId: null,
        authUrl: null,
        status: "completed",
        message: "Account added successfully.",
        error: null,
        startedAt: this.loginFlow.startedAt,
        completedAt: new Date().toISOString(),
      };
      this.statusMessage = "Account added and switched.";
      this.errorMessage = null;
      await this.broadcastState();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to finish login.";
      this.loginFlow = {
        active: false,
        loginId: null,
        authUrl: null,
        status: "error",
        message: null,
        error: message,
        startedAt: this.loginFlow.startedAt,
        completedAt: new Date().toISOString(),
      };
      this.errorMessage = message;
      await this.broadcastState();
    }
  }

  private async readCurrentAccount(): Promise<AccountRegistryEntry | null> {
    const [auth, savedAccounts] = await Promise.all([
      readCurrentAuthBlob(),
      loadRegistry(),
    ]);

    let accountResponse: AccountReadResponse;
    try {
      accountResponse = (await this.appServer.request("account/read", {
        refreshToken: true,
      })) as AccountReadResponse;
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : "Failed to read the active Codex account.";
      this.errorMessage = this.errorMessage ?? message;
      return null;
    }

    if (!accountResponse.account || accountResponse.account.type !== "chatgpt") {
      if (accountResponse.requiresOpenaiAuth) {
        this.noticeMessage = "Sign in with ChatGPT to add and switch accounts.";
      }
      return null;
    }

    let usageSnapshot = null;
    try {
      const rateLimitResponse = (await this.appServer.request(
        "account/rateLimits/read",
        null,
      )) as RateLimitsResponse;
      usageSnapshot = normalizeUsageSnapshot(
        selectRateLimitSnapshot(rateLimitResponse),
        "live",
        normalizePlanType(accountResponse.account.planType),
      );
    } catch (error) {
      this.noticeMessage =
        this.noticeMessage ??
        (error instanceof Error
          ? error.message
          : "Unable to load the live usage snapshot right now.");
    }

    const identity = {
      ...deriveAccountIdentity(auth),
      email: accountResponse.account.email,
    };
    const existing = findMatchingAccount(savedAccounts, identity);
    const now = new Date().toISOString();

    return {
      id: existing?.id ?? identity.chatgptAccountId ?? accountResponse.account.email,
      email: accountResponse.account.email,
      maskedEmail: maskEmail(accountResponse.account.email),
      planType:
        normalizePlanType(accountResponse.account.planType) ??
        usageSnapshot?.planType ??
        null,
      chatgptAccountId: identity.chatgptAccountId,
      addedAt: existing?.addedAt ?? now,
      lastUsedAt: existing?.lastUsedAt ?? now,
      usageSnapshot,
      authKeychainKey: existing?.authKeychainKey,
      usageError: null,
      active: true,
      isCurrent: true,
      current: true,
    };
  }

  private async resolveSavedAccount(
    identity: AccountIdentity,
  ): Promise<AccountRegistryEntry | null> {
    const accounts = await loadRegistry();

    if (identity.id) {
      const byId = accounts.find((account) => account.id === identity.id);
      if (byId) {
        return byId;
      }
    }

    return findMatchingAccount(accounts, {
      email: identity.email ?? null,
      chatgptAccountId: identity.chatgptAccountId ?? null,
    });
  }

  private isSnapshotStale(account: AccountRegistryEntry): boolean {
    if (!account.usageSnapshot?.updatedAt) {
      return true;
    }

    const updatedAt =
      typeof account.usageSnapshot.updatedAt === "number"
        ? account.usageSnapshot.updatedAt
        : Date.parse(account.usageSnapshot.updatedAt);
    if (!Number.isFinite(updatedAt)) {
      return true;
    }

    return Date.now() - updatedAt >= SAVED_ACCOUNT_STALE_MS;
  }

  private async getCodexCliVersion(): Promise<string> {
    if (!this.cliVersionPromise) {
      this.cliVersionPromise = Promise.resolve().then(() => {
        const result = Bun.spawnSync({
          cmd: ["codex", "--version"],
          stdout: "pipe",
          stderr: "pipe",
        });
        const output = `${result.stdout.toString()} ${result.stderr.toString()}`;
        const match = output.match(/(\d+\.\d+\.\d+)/);
        return match?.[1] ?? "0.115.0";
      });
    }

    return this.cliVersionPromise;
  }

  private async broadcastState(state?: DashboardState): Promise<void> {
    const nextState = state ?? (await this.getDashboardState());
    try {
      mainWindow.webview.rpc?.send.dashboardStateUpdated({
        state: nextState,
      });
    } catch {
      // Renderer may not be ready yet.
    }
    if (USE_TRAY_MENU) {
      try {
        tray.setMenu(buildTrayMenu(nextState));
      } catch {
        // Tray may not be ready yet.
      }
    }
  }

  private createLoginFlow(): LoginFlowState {
    return {
      active: false,
      loginId: null,
      authUrl: null,
      status: null,
      message: null,
      error: null,
      startedAt: null,
      completedAt: null,
    };
  }

  private compactEphemeralState(): void {
    if (
      (this.loginFlow.status === "completed" ||
        this.loginFlow.status === "canceled" ||
        this.loginFlow.status === "error") &&
      this.loginFlow.completedAt
    ) {
      const completedAt = Date.parse(this.loginFlow.completedAt);
      if (!Number.isNaN(completedAt) && Date.now() - completedAt > 15_000) {
        this.loginFlow = this.createLoginFlow();
      }
    }
  }
}

async function mapWithConcurrency<T>(
  values: T[],
  concurrency: number,
  worker: (value: T) => Promise<void>,
): Promise<void> {
  let index = 0;
  const runners = Array.from(
    { length: Math.min(concurrency, values.length) },
    async () => {
      while (index < values.length) {
        const currentIndex = index;
        index += 1;
        await worker(values[currentIndex]!);
      }
    },
  );

  await Promise.all(runners);
}

const controller = new DashboardController();

function formatUsageBar(usedPercent: number): string {
  const filled = Math.round(usedPercent / 10);
  const empty = 10 - filled;
  return "▓".repeat(filled) + "░".repeat(empty) + ` ${Math.round(usedPercent)}%`;
}

function formatResetTime(resetsAt: number | string | null): string {
  if (!resetsAt) return "";
  const resetMs = typeof resetsAt === "number" ? resetsAt : Date.parse(resetsAt);
  if (!Number.isFinite(resetMs)) return "";
  const diffMins = Math.max(0, Math.round((resetMs - Date.now()) / 60_000));
  if (diffMins < 60) return `${diffMins}m`;
  const hours = Math.floor(diffMins / 60);
  const mins = diffMins % 60;
  return mins > 0 ? `${hours}h${mins}m` : `${hours}h`;
}

function buildTrayMenu(state: DashboardState): Array<MenuItemConfig> {
  const menu: Array<MenuItemConfig> = [];
  const prefs = state.preferences;

  // --- Current account section ---
  if (state.currentAccount) {
    const acct = state.currentAccount;
    const displayEmail = prefs.maskEmails ? acct.maskedEmail : acct.email;
    const planLabel = acct.planType ? ` (${acct.planType})` : "";
    menu.push({
      type: "normal",
      label: `✦ ${displayEmail}${planLabel}`,
      enabled: false,
    });

    if (acct.usageSnapshot?.primary) {
      const w = acct.usageSnapshot.primary;
      const resetStr = formatResetTime(w.resetsAt);
      menu.push({
        type: "normal",
        label: `   ${w.label}: ${formatUsageBar(w.usedPercent)}${resetStr ? `  resets ${resetStr}` : ""}`,
        enabled: false,
      });
    }
    if (acct.usageSnapshot?.secondary) {
      const w = acct.usageSnapshot.secondary;
      const resetStr = formatResetTime(w.resetsAt);
      menu.push({
        type: "normal",
        label: `   ${w.label}: ${formatUsageBar(w.usedPercent)}${resetStr ? `  resets ${resetStr}` : ""}`,
        enabled: false,
      });
    }

    if (!acct.authKeychainKey) {
      menu.push({
        type: "normal",
        label: "   Save Current Account",
        action: "save-current",
      });
    }
  } else if (state.notice) {
    menu.push({ type: "normal", label: state.notice, enabled: false });
  } else {
    menu.push({ type: "normal", label: "No active account", enabled: false });
  }

  // --- Saved accounts section ---
  const savedAccounts = state.savedAccounts.filter((a) => !a.isCurrent && !a.current);
  if (savedAccounts.length > 0) {
    menu.push({ type: "divider" });
    menu.push({ type: "normal", label: "Switch To", enabled: false });

    for (const acct of savedAccounts) {
      const displayEmail = prefs.maskEmails ? acct.maskedEmail : acct.email;
      const planLabel = acct.planType ? ` (${acct.planType})` : "";
      let usageHint = "";
      if (acct.usageSnapshot?.primary) {
        usageHint = ` — ${Math.round(acct.usageSnapshot.primary.usedPercent)}%`;
      }
      menu.push({
        type: "normal",
        label: `${displayEmail}${planLabel}${usageHint}`,
        action: "switch-account",
        data: { id: acct.id, email: acct.email },
      });
    }
  }

  // --- Actions ---
  menu.push({ type: "divider" });
  menu.push({
    type: "normal",
    label: "Add Account…",
    action: "add-account",
  });
  menu.push({
    type: "normal",
    label: state.refreshing ? "Refreshing…" : "Refresh",
    action: "refresh",
    enabled: !state.refreshing,
  });

  // --- Status / error ---
  if (state.error) {
    menu.push({ type: "divider" });
    menu.push({ type: "normal", label: `⚠ ${state.error}`, enabled: false });
  }

  // --- Footer ---
  menu.push({ type: "divider" });
  menu.push({
    type: "normal",
    label: "Settings…",
    action: "open-settings",
  });
  menu.push({
    type: "normal",
    label: "OpenAI Status",
    action: "open-status",
  });
  menu.push({ type: "divider" });
  menu.push({
    type: "normal",
    label: "Quit CX Switch",
    action: "quit",
  });

  return menu;
}

async function updateTrayMenu(): Promise<void> {
  if (!USE_TRAY_MENU) return;
  try {
    const state = await controller.getDashboardState();
    tray.setMenu(buildTrayMenu(state));
  } catch (error) {
    console.error("[tray-menu] failed to update:", error);
  }
}

ApplicationMenu.setApplicationMenu([
  {
    submenu: [{ label: "Quit", role: "quit" }],
  },
]);

const mainWindow = new BrowserWindow({
  title: APP_NAME,
  url: appUrl,
  rpc,
  frame: {
    x: HIDDEN_X,
    y: HIDDEN_Y,
    width: POPUP_WIDTH,
    height: POPUP_HEIGHT,
  },
  titleBarStyle: "hidden",
  transparent: true,
  hidden: false,
  styleMask: {
    Closable: false,
    Miniaturizable: false,
    Resizable: false,
  },
});

mainWindow.setAlwaysOnTop(true);
mainWindow.setVisibleOnAllWorkspaces(true);

const tray = new Tray({
  title: "CX",
});

function hidePopup(): void {
  controller.setPopupVisible(false);
  mainWindow.setFrame(HIDDEN_X, HIDDEN_Y, POPUP_WIDTH, POPUP_HEIGHT);
}

function showPopup(): void {
  const display = Screen.getPrimaryDisplay();
  const trayBounds = tray.getBounds();
  const trayBoundsLookValid =
    Number.isFinite(trayBounds.x) &&
    Number.isFinite(trayBounds.y) &&
    Number.isFinite(trayBounds.width) &&
    Number.isFinite(trayBounds.height) &&
    trayBounds.width > 0 &&
    trayBounds.height > 0;

  const fallbackX = Math.max(
    display.workArea.x + 16,
    display.workArea.x + display.workArea.width - POPUP_WIDTH - 16,
  );
  const fallbackY = display.workArea.y + 40;

  const x = trayBoundsLookValid
    ? Math.max(
        16,
        Math.round(trayBounds.x + trayBounds.width / 2 - POPUP_WIDTH / 2),
      )
    : fallbackX;
  const y = fallbackY;

  console.log(
    `[tray] show popup at x=${x}, y=${y}, tray=(${trayBounds.x},${trayBounds.y},${trayBounds.width},${trayBounds.height}), workArea=(${display.workArea.x},${display.workArea.y},${display.workArea.width},${display.workArea.height})`,
  );
  controller.setPopupVisible(true);
  popupOpenedAt = Date.now();
  mainWindow.setFrame(x, y, POPUP_WIDTH, POPUP_HEIGHT);
  mainWindow.show();
  mainWindow.focus();
  void controller.handlePopupOpened();
}

tray.on("tray-clicked", (event: unknown) => {
  const { action, data } = (event ?? {}) as { action?: string; data?: unknown };
  console.log("[tray] clicked, action:", action, "data:", data);

  if (USE_TRAY_MENU) {
    // Handle menu item actions
    switch (action) {
      case "switch-account": {
        const identity = data as AccountIdentity;
        void controller.switchAccount(identity);
        break;
      }
      case "save-current":
        void controller.saveCurrentAccount();
        break;
      case "add-account":
        void controller.startAddAccount();
        break;
      case "refresh":
        void controller.refreshSavedAccounts(true);
        break;
      case "open-settings":
        controller.openSettings();
        break;
      case "open-status":
        controller.openStatusPage();
        break;
      case "quit":
        void controller.quitApp();
        break;
      default:
        // Tray icon itself clicked (no action) — refresh menu
        void updateTrayMenu();
        break;
    }
    return;
  }

  // Popup mode
  if (controller.isPopupVisible()) {
    hidePopup();
    return;
  }
  showPopup();
});

mainWindow.on("blur", () => {
  if (USE_TRAY_MENU) return;
  console.log("[window] blur");
  if (Date.now() - popupOpenedAt < 800) {
    console.log("[window] blur ignored during popup warmup");
    return;
  }

  console.log("[window] blur ignored while debugging visibility");
});

Utils.setDockIconVisible(false);

// Initial tray menu build
void updateTrayMenu();

Electrobun.events.on("before-quit", async () => {
  await controller.shutdown();
});
