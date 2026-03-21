import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { mkdir } from "node:fs/promises";
import { Utils } from "electrobun/bun";
import type {
  AccountAuthBlob,
  AccountIdentity,
  AccountRegistryEntry,
  AppPreferences,
  DashboardState,
  LoginFlowState,
  PlanType,
  UsageSnapshot,
  UsageWindow,
} from "../shared/rpc";

type RateLimitWindow = {
  usedPercent: number;
  windowDurationMins: number | null;
  resetsAt: number | null;
};

type RateLimitSnapshot = {
  limitId: string | null;
  limitName: string | null;
  primary: RateLimitWindow | null;
  secondary: RateLimitWindow | null;
  credits: {
    hasCredits: boolean;
    unlimited: boolean;
    balance: string | null;
  } | null;
  planType: PlanType | null;
};

type CodexAccountReadResult = {
  account:
    | {
        type: "chatgpt";
        email: string;
        planType: PlanType;
      }
    | {
        type: "apiKey";
      }
    | null;
  requiresOpenaiAuth: boolean;
};

type LoginStartResponse = {
  type: "chatgpt";
  loginId: string;
  authUrl: string;
};

type LoginCompletedNotification = {
  loginId: string | null;
  success: boolean;
  error: string | null;
};

type JSONValue = Record<string, unknown>;

const APP_NAME = "CX Switch";
const KEYCHAIN_SERVICE = "com.nova-infra.cx-switch";
const AUTH_PATH = join(homedir(), ".codex", "auth.json");
const DATA_DIR = Utils.paths.userData;
const REGISTRY_PATH = join(DATA_DIR, "registry.json");
const PREFS_PATH = join(DATA_DIR, "preferences.json");
const CACHE_DIR = join(Utils.paths.userCache, "account-snapshots");
const STATUS_PAGE_URL = "https://status.openai.com";
const DEFAULT_REFRESH_POLICY = "Refreshes saved accounts on open and every 60 seconds.";
const OPENAI_PROBE_URL = "https://chatgpt.com/backend-api/codex/responses";
const OPENAI_PROBE_VERSION = "0.104.0";
const OPENAI_PROBE_MODEL = "gpt-5.1-codex";
const PROBE_CONCURRENCY = 2;
const PROBE_TIMEOUT_MS = 15_000;
const SNAPSHOT_STALE_MS = 60_000;

function isRecord(value: unknown): value is JSONValue {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function cloneJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function nowIso() {
  return new Date().toISOString();
}

function clampPercent(value: unknown): number {
  const parsed =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : 0;
  if (!Number.isFinite(parsed)) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.round(parsed)));
}

function formatMaskedEmail(email: string) {
  const [local, domain] = email.split("@");
  if (!domain) {
    return email;
  }
  if (local.length <= 2) {
    return `${local[0] ?? ""}••••@${domain}`;
  }
  return `${local.slice(0, 1)}••••${local.slice(-1)}@${domain}`;
}

function durationLabel(minutes: number | null | undefined) {
  if (minutes === 300) return "5 Hours";
  if (minutes === 10_080) return "Weekly";
  if (minutes == null) return "Usage";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  if (hours % 24 === 0) return `${hours / 24}d`;
  return `${hours}h`;
}

function normalizeResetAt(value: number | null | undefined): number | null {
  if (value == null || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

function normalizeRateLimitWindow(
  window: RateLimitWindow | null,
  fallbackDuration: number,
): UsageWindow {
  return {
    label: durationLabel(window?.windowDurationMins ?? fallbackDuration),
    windowDurationMins: window?.windowDurationMins ?? fallbackDuration,
    usedPercent: clampPercent(window?.usedPercent),
    resetsAt: normalizeResetAt(window?.resetsAt ?? null),
  };
}

function normalizeRateLimitSnapshot(snapshot: RateLimitSnapshot | null): UsageSnapshot | null {
  if (!snapshot) {
    return null;
  }

  const windows: UsageWindow[] = [];
  if (snapshot.primary) {
    windows.push(normalizeRateLimitWindow(snapshot.primary, 300));
  }
  if (snapshot.secondary) {
    windows.push(normalizeRateLimitWindow(snapshot.secondary, 10_080));
  }
  windows.sort((left, right) => left.windowDurationMins - right.windowDurationMins);

  return {
    limitId: snapshot.limitId,
    planType: snapshot.planType,
    updatedAt: nowIso(),
    windows,
    primary: windows.find((window) => window.windowDurationMins === 300) ?? windows[0] ?? null,
    secondary: windows.find((window) => window.windowDurationMins === 10_080) ?? windows[1] ?? null,
    credits: snapshot.credits,
  };
}

function normalizeAccountIdentity(entry: AccountRegistryEntry | null | undefined): string {
  if (!entry) {
    return "";
  }

  return entry.chatgptAccountId || entry.email || entry.id;
}

function deriveAuthIdentity(blob: AccountAuthBlob | null) {
  const tokens = blob?.tokens ?? null;
  const accountId = tokens?.account_id?.trim() || "";
  const email = blob?.tokens?.id_token ? decodeEmailFromJwt(blob.tokens.id_token) : "";
  return {
    chatgptAccountId: accountId || email,
    email,
  };
}

function decodeJwtPayload(token: string): JSONValue | null {
  const parts = token.split(".");
  if (parts.length < 2) {
    return null;
  }
  try {
    const payload = parts[1];
    const padding = payload.length % 4;
    const normalized =
      padding === 0 ? payload : payload + "=".repeat(4 - padding);
    const decoded = Buffer.from(normalized.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
    return JSON.parse(decoded) as JSONValue;
  } catch {
    return null;
  }
}

function decodeEmailFromJwt(token: string): string {
  const payload = decodeJwtPayload(token);
  if (!payload) {
    return "";
  }
  const nested = payload["https://api.openai.com/auth"];
  if (isRecord(nested) && typeof nested.email === "string") {
    return nested.email;
  }
  if (typeof payload.email === "string") {
    return payload.email;
  }
  return "";
}

async function ensureParentDir(path: string) {
  await mkdir(dirname(path), { recursive: true });
}

async function readJsonFile<T>(path: string): Promise<T | null> {
  try {
    const text = await Bun.file(path).text();
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}

async function writeJsonFile(path: string, value: unknown) {
  await ensureParentDir(path);
  const tempPath = join(tmpdir(), `cx-switch-${crypto.randomUUID()}.tmp`);
  await Bun.write(tempPath, `${JSON.stringify(value, null, 2)}\n`);
  await Bun.write(path, await Bun.file(tempPath).bytes());
}

async function atomicWriteText(path: string, contents: string) {
  await ensureParentDir(path);
  const tempPath = join(tmpdir(), `cx-switch-${crypto.randomUUID()}.tmp`);
  await Bun.write(tempPath, contents);
  await Bun.write(path, await Bun.file(tempPath).bytes());
}

function runSecurity(args: string[]): string {
  const result = Bun.spawnSync(["security", ...args], {
    stdout: "pipe",
    stderr: "pipe",
    cwd: homedir(),
  });

  const stdout = new TextDecoder().decode(result.stdout);
  const stderr = new TextDecoder().decode(result.stderr);

  if (result.exitCode !== 0) {
    throw new Error(stderr.trim() || stdout.trim() || `security exited with ${result.exitCode}`);
  }

  return stdout.trim();
}

async function saveAuthToKeychain(key: string, blob: AccountAuthBlob) {
  const encoded = Buffer.from(JSON.stringify(blob)).toString("base64");
  runSecurity([
    "add-generic-password",
    "-U",
    "-a",
    key,
    "-s",
    KEYCHAIN_SERVICE,
    "-w",
    encoded,
  ]);
}

async function readAuthFromKeychain(key: string): Promise<AccountAuthBlob | null> {
  try {
    const encoded = runSecurity(["find-generic-password", "-a", key, "-s", KEYCHAIN_SERVICE, "-w"]);
    if (!encoded) {
      return null;
    }
    return JSON.parse(Buffer.from(encoded, "base64").toString("utf8")) as AccountAuthBlob;
  } catch {
    return null;
  }
}

async function deleteAuthFromKeychain(key: string) {
  try {
    runSecurity(["delete-generic-password", "-a", key, "-s", KEYCHAIN_SERVICE]);
  } catch {
    // The item might already be missing.
  }
}

function buildUsageSnapshotFromCodexRateLimits(snapshot: JSONValue | null): UsageSnapshot | null {
  if (!snapshot || !isRecord(snapshot)) {
    return null;
  }

  const primary = isRecord(snapshot.primary) ? snapshot.primary : null;
  const secondary = isRecord(snapshot.secondary) ? snapshot.secondary : null;
  const windows: UsageWindow[] = [];

  if (primary) {
    windows.push({
      label: durationLabel(asNumber(primary.windowDurationMins) ?? 300),
      windowDurationMins: asNumber(primary.windowDurationMins) ?? 300,
      usedPercent: clampPercent(primary.usedPercent),
      resetsAt: asNumber(primary.resetsAt),
    });
  }
  if (secondary) {
    windows.push({
      label: durationLabel(asNumber(secondary.windowDurationMins) ?? 10_080),
      windowDurationMins: asNumber(secondary.windowDurationMins) ?? 10_080,
      usedPercent: clampPercent(secondary.usedPercent),
      resetsAt: asNumber(secondary.resetsAt),
    });
  }
  windows.sort((left, right) => left.windowDurationMins - right.windowDurationMins);

  return {
    limitId: typeof snapshot.limitId === "string" ? snapshot.limitId : null,
    planType: typeof snapshot.planType === "string" ? (snapshot.planType as PlanType) : null,
    updatedAt: nowIso(),
    windows,
    primary: windows.find((window) => window.windowDurationMins === 300) ?? windows[0] ?? null,
    secondary: windows.find((window) => window.windowDurationMins === 10_080) ?? windows[1] ?? null,
    credits: isRecord(snapshot.credits)
      ? {
          hasCredits: Boolean(snapshot.credits.hasCredits),
          unlimited: Boolean(snapshot.credits.unlimited),
          balance: typeof snapshot.credits.balance === "string" ? snapshot.credits.balance : null,
        }
      : null,
  };
}

function buildUsageSnapshotFromHeaders(headers: Headers): UsageSnapshot | null {
  const primaryUsed = headers.get("x-codex-primary-used-percent");
  const primaryWindow = headers.get("x-codex-primary-window-minutes");
  const primaryReset = headers.get("x-codex-primary-reset-after-seconds");
  const secondaryUsed = headers.get("x-codex-secondary-used-percent");
  const secondaryWindow = headers.get("x-codex-secondary-window-minutes");
  const secondaryReset = headers.get("x-codex-secondary-reset-after-seconds");

  const windows: UsageWindow[] = [];
  if (primaryUsed != null || primaryWindow != null) {
    windows.push({
      label: durationLabel(Number(primaryWindow)),
      windowDurationMins: Number(primaryWindow) || 300,
      usedPercent: clampPercent(primaryUsed),
      resetsAt: Number(primaryReset) ? Math.floor(Date.now() / 1000) + Number(primaryReset) : null,
    });
  }
  if (secondaryUsed != null || secondaryWindow != null) {
    windows.push({
      label: durationLabel(Number(secondaryWindow)),
      windowDurationMins: Number(secondaryWindow) || 10_080,
      usedPercent: clampPercent(secondaryUsed),
      resetsAt: Number(secondaryReset) ? Math.floor(Date.now() / 1000) + Number(secondaryReset) : null,
    });
  }

  if (windows.length === 0) {
    return null;
  }

  windows.sort((left, right) => left.windowDurationMins - right.windowDurationMins);

  return {
    limitId: "codex",
    planType: null,
    updatedAt: nowIso(),
    windows,
    primary: windows.find((window) => window.windowDurationMins === 300) ?? windows[0] ?? null,
    secondary: windows.find((window) => window.windowDurationMins === 10_080) ?? windows[1] ?? null,
    credits: null,
  };
}

function isStaleSnapshot(snapshot: UsageSnapshot | null | undefined) {
  if (!snapshot?.updatedAt) {
    return true;
  }

  const updatedAt = Date.parse(snapshot.updatedAt);
  if (!Number.isFinite(updatedAt)) {
    return true;
  }

  return Date.now() - updatedAt >= SNAPSHOT_STALE_MS;
}

function compareEntryIdentity(
  left: AccountRegistryEntry,
  right:
    | AccountIdentity
    | Pick<AccountRegistryEntry, "id" | "chatgptAccountId" | "email" | "maskedEmail">
    | null
    | undefined,
) {
  if (!right) {
    return false;
  }

  return Boolean(
    (right.chatgptAccountId && left.chatgptAccountId === right.chatgptAccountId) ||
      (right.email && left.email === right.email) ||
      (right.id && left.id === right.id),
  );
}

function defaultPreferences(): AppPreferences {
  return {
    maskEmails: true,
    refreshPolicy: DEFAULT_REFRESH_POLICY,
    dataFolder: DATA_DIR,
  };
}

class CodexAppServerClient {
  private process: Bun.Subprocess | null = null;
  private stdoutBuffer = "";
  private stderrBuffer = "";
  private requestId = 0;
  private pending = new Map<
    number,
    {
      resolve: (value: unknown) => void;
      reject: (error: Error) => void;
    }
  >();
  private notificationListeners = new Set<(notification: JSONValue) => void>();
  private initializePromise: Promise<unknown> | null = null;

  onNotification(listener: (notification: JSONValue) => void) {
    this.notificationListeners.add(listener);
    return () => this.notificationListeners.delete(listener);
  }

  private emitNotification(notification: JSONValue) {
    for (const listener of this.notificationListeners) {
      try {
        listener(notification);
      } catch (error) {
        console.error("codex notification listener failed:", error);
      }
    }
  }

  private handleLine(line: string) {
    if (!line.trim()) {
      return;
    }

    try {
      const packet = JSON.parse(line) as JSONValue;
      if (typeof packet.id === "number") {
        const pending = this.pending.get(packet.id);
        if (!pending) {
          return;
        }
        this.pending.delete(packet.id);
        if ("error" in packet && packet.error != null) {
          const message =
            isRecord(packet.error) && typeof packet.error.message === "string"
              ? packet.error.message
              : "codex app-server request failed";
          pending.reject(new Error(message));
          return;
        }
        pending.resolve(packet.result);
        return;
      }

      if (typeof packet.method === "string" && packet.params != null) {
        this.emitNotification(packet);
      }
    } catch (error) {
      console.error("failed to parse codex app-server line:", line, error);
    }
  }

  private async pump(stream: ReadableStream<Uint8Array>) {
    const reader = stream.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      this.stdoutBuffer += decoder.decode(value, { stream: true });
      let index = this.stdoutBuffer.indexOf("\n");
      while (index >= 0) {
        const line = this.stdoutBuffer.slice(0, index).trim();
        this.stdoutBuffer = this.stdoutBuffer.slice(index + 1);
        this.handleLine(line);
        index = this.stdoutBuffer.indexOf("\n");
      }
    }
  }

  private async pumpStderr(stream: ReadableStream<Uint8Array>) {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      this.stderrBuffer += decoder.decode(value, { stream: true });
      let index = this.stderrBuffer.indexOf("\n");
      while (index >= 0) {
        const line = this.stderrBuffer.slice(0, index).trim();
        this.stderrBuffer = this.stderrBuffer.slice(index + 1);
        if (line) {
          console.log(`[codex app-server] ${line}`);
        }
        index = this.stderrBuffer.indexOf("\n");
      }
    }
  }

  private async startProcess() {
    if (this.process) {
      return;
    }

    const subprocess = Bun.spawn(["codex", "app-server", "--listen", "stdio://"], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    this.process = subprocess;

    if (subprocess.stdout) {
      void this.pump(subprocess.stdout);
    }
    if (subprocess.stderr) {
      void this.pumpStderr(subprocess.stderr);
    }

    this.initializePromise = this.sendRequest("initialize", {
      clientInfo: {
        name: APP_NAME,
        version: "0.1.3",
      },
      capabilities: null,
    });

    await this.initializePromise;
  }

  async ensureStarted() {
    if (!this.process) {
      await this.startProcess();
    } else if (!this.initializePromise) {
      this.initializePromise = this.sendRequest("initialize", {
        clientInfo: {
          name: APP_NAME,
          version: "0.1.3",
        },
        capabilities: null,
      });
      await this.initializePromise;
    } else {
      await this.initializePromise;
    }
  }

  async restart() {
    await this.stop();
    await this.ensureStarted();
  }

  async stop() {
    if (!this.process) {
      return;
    }

    try {
      this.process.kill();
    } catch {
      // ignore
    }

    this.process = null;
    this.initializePromise = null;
    this.pending.clear();
  }

  async request(method: string, params: JSONValue | null = null): Promise<unknown> {
    await this.ensureStarted();
    return await this.sendRequest(method, params);
  }

  private async sendRequest(method: string, params: JSONValue | null = null): Promise<unknown> {
    if (!this.process?.stdin) {
      throw new Error("codex app-server stdin is not available");
    }

    const id = ++this.requestId;
    const payload = JSON.stringify({ id, method, params }) + "\n";

    const response = new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });

    await (this.process.stdin as unknown as { write(data: string): Promise<unknown> }).write(
      payload,
    );
    return response;
  }

  async readAccount() {
    const response = (await this.request("account/read", {})) as CodexAccountReadResult;
    return response;
  }

  async readRateLimits() {
    return (await this.request("account/rateLimits/read", {})) as {
      rateLimits: unknown;
      rateLimitsByLimitId: Record<string, unknown> | null;
    };
  }

  async startChatgptLogin() {
    return (await this.request("account/login/start", { type: "chatgpt" })) as LoginStartResponse;
  }

  async cancelLogin(loginId: string) {
    return await this.request("account/login/cancel", { loginId });
  }
}

class LocalStore {
  private registryCache: AccountRegistryEntry[] | null = null;
  private preferencesCache: AppPreferences | null = null;

  async loadPreferences(): Promise<AppPreferences> {
    if (this.preferencesCache) {
      return cloneJson(this.preferencesCache);
    }

    const stored = await readJsonFile<Partial<AppPreferences>>(PREFS_PATH);
    const preferences: AppPreferences = {
      ...defaultPreferences(),
      ...(stored ?? {}),
    };

    this.preferencesCache = preferences;
    return cloneJson(preferences);
  }

  async savePreferences(preferences: AppPreferences) {
    this.preferencesCache = cloneJson(preferences);
    await writeJsonFile(PREFS_PATH, preferences);
  }

  async loadRegistry(): Promise<AccountRegistryEntry[]> {
    if (this.registryCache) {
      return cloneJson(this.registryCache);
    }

    const stored = await readJsonFile<AccountRegistryEntry[]>(REGISTRY_PATH);
    this.registryCache = Array.isArray(stored) ? stored : [];
    return cloneJson(this.registryCache);
  }

  async saveRegistry(entries: AccountRegistryEntry[]) {
    this.registryCache = cloneJson(entries);
    await writeJsonFile(REGISTRY_PATH, entries);
  }

  async readAuthBlob(): Promise<AccountAuthBlob | null> {
    return await readJsonFile<AccountAuthBlob>(AUTH_PATH);
  }

  async writeAuthBlob(blob: AccountAuthBlob) {
    await atomicWriteText(AUTH_PATH, `${JSON.stringify(blob, null, 2)}\n`);
  }

  async saveAccountAuth(key: string, blob: AccountAuthBlob) {
    await saveAuthToKeychain(key, blob);
  }

  async readAccountAuth(key: string) {
    return await readAuthFromKeychain(key);
  }

  async deleteAccountAuth(key: string) {
    await deleteAuthFromKeychain(key);
  }

  async ensureCacheDir() {
    await mkdir(CACHE_DIR, { recursive: true });
  }
}

export class DashboardController {
  private state: DashboardState;
  private refreshPromise: Promise<void> = Promise.resolve();
  private loginFlow: LoginFlowState = {
    active: false,
    loginId: null,
    authUrl: null,
    status: null,
    message: null,
    error: null,
  };

  constructor(
    private readonly appServer: CodexAppServerClient,
    private readonly store: LocalStore,
    private readonly rpc: {
      send: {
        dashboardStateUpdated: (state: DashboardState) => void;
      };
    },
  ) {
    this.state = {
      appName: APP_NAME,
      loading: true,
      refreshing: false,
      updatedAt: null,
      currentAccount: null,
      savedAccounts: [],
      preferences: defaultPreferences(),
      loginFlow: cloneJson(this.loginFlow),
      status: null,
      error: null,
      notice: null,
    };

    this.appServer.onNotification((notification) => {
      if (notification.method === "account/login/completed") {
        void this.handleLoginCompleted(notification.params as LoginCompletedNotification);
      }
      if (notification.method === "account/updated" || notification.method === "account/rateLimits/updated") {
        void this.reloadDashboard({ refreshSavedAccounts: true });
      }
    });
  }

  private setState(next: Partial<DashboardState>) {
    this.state = {
      ...this.state,
      ...next,
      loginFlow: next.loginFlow ? cloneJson(next.loginFlow) : this.state.loginFlow,
    };
    this.rpc.send.dashboardStateUpdated(cloneJson(this.state));
  }

  private async loadCurrentAccount() {
    const authBlob = await this.store.readAuthBlob();
    const identity = deriveAuthIdentity(authBlob);
    const accountResult = await this.appServer.readAccount();
    const rateLimitResult = await this.appServer.readRateLimits();
    const rateLimitSnapshot = normalizeRateLimitSnapshot(
      (rateLimitResult.rateLimitsByLimitId?.codex ?? rateLimitResult.rateLimits) as RateLimitSnapshot,
    );

    if (!accountResult.account || accountResult.account.type !== "chatgpt") {
      return {
        currentAccount: null,
        rateLimits: rateLimitSnapshot,
        authIdentity: identity,
        error: null,
      };
    }

    const currentAccount: AccountRegistryEntry = {
      id: identity.chatgptAccountId || accountResult.account.email,
      email: accountResult.account.email,
      maskedEmail: formatMaskedEmail(accountResult.account.email),
      planType: accountResult.account.planType,
      chatgptAccountId: identity.chatgptAccountId || accountResult.account.email,
      addedAt: nowIso(),
      lastUsedAt: nowIso(),
      usageSnapshot: rateLimitSnapshot,
      authKeychainKey: identity.chatgptAccountId || accountResult.account.email,
    };

    return {
      currentAccount,
      rateLimits: rateLimitSnapshot,
      authIdentity: identity,
      error: null,
    };
  }

  private async loadDashboard({ refreshSavedAccounts = false, background = false } = {}) {
    const [preferences, registry] = await Promise.all([
      this.store.loadPreferences(),
      this.store.loadRegistry(),
    ]);

    const current = await this.loadCurrentAccount().catch((error) => {
      const message = error instanceof Error ? error.message : "Failed to read current Codex account.";
      return {
        currentAccount: null,
        rateLimits: null,
        authIdentity: { chatgptAccountId: "", email: "" },
        error: message,
      };
    });
    const currentError = (current as { error?: string | null }).error ?? null;

    const currentAccount = current.currentAccount;
    const currentIdentity = current.authIdentity.chatgptAccountId || current.authIdentity.email || "";
    const currentAccountIdentity = currentAccount
      ? {
          id: currentAccount.id,
          email: currentAccount.email,
          chatgptAccountId: currentAccount.chatgptAccountId,
        }
      : {
          id: currentIdentity,
          email: current.authIdentity.email,
          chatgptAccountId: currentIdentity,
        };
    const savedAccounts = registry
      .map((entry) => ({
        ...entry,
        maskedEmail: preferences.maskEmails ? entry.maskedEmail || formatMaskedEmail(entry.email) : entry.email,
      }))
      .filter((entry) => !compareEntryIdentity(entry, currentAccountIdentity))
      .sort((left, right) => left.email.localeCompare(right.email));

    const notice = background
      ? "Refreshing saved account snapshots in the background."
      : savedAccounts.length > 0
        ? "Ready"
        : "Add an account to get started.";

    this.state = {
      appName: APP_NAME,
      loading: false,
      refreshing: refreshSavedAccounts,
      updatedAt: nowIso(),
      currentAccount,
      savedAccounts,
      preferences,
      loginFlow: cloneJson(this.loginFlow),
      status: currentError ?? notice,
      error: currentError,
      notice,
    };

    this.rpc.send.dashboardStateUpdated(cloneJson(this.state));

    if (refreshSavedAccounts) {
      this.enqueueSavedAccountRefresh(savedAccounts).catch((error) => {
        const message = error instanceof Error ? error.message : "Failed to refresh saved accounts.";
        this.setState({ refreshing: false, status: message, error: message });
      });
    }

    return cloneJson(this.state);
  }

  private enqueueSavedAccountRefresh(entries: AccountRegistryEntry[]) {
    this.refreshPromise = this.refreshPromise.then(() => this.refreshSavedAccountSnapshots(entries));
    return this.refreshPromise;
  }

  private async refreshSavedAccountSnapshots(entries: AccountRegistryEntry[], force = false) {
    await this.store.ensureCacheDir();
    const staleEntries = force ? entries : entries.filter((entry) => isStaleSnapshot(entry.usageSnapshot));
    if (staleEntries.length === 0) {
      this.setState({ refreshing: false });
      return;
    }

    const updatedEntries = [...entries];
    let cursor = 0;

    const worker = async () => {
      while (cursor < staleEntries.length) {
        const entry = staleEntries[cursor++];
        try {
          const snapshot = await this.probeSavedAccountUsage(entry);
          if (snapshot) {
            const index = updatedEntries.findIndex((candidate) => candidate.id === entry.id);
            if (index >= 0) {
              updatedEntries[index] = {
                ...updatedEntries[index],
                usageSnapshot: snapshot,
                lastUsedAt: nowIso(),
              };
            }
          }
        } catch (error) {
          console.warn("saved account probe failed:", entry.email, error);
        }
      }
    };

    await Promise.all(Array.from({ length: Math.min(PROBE_CONCURRENCY, staleEntries.length) }, worker));
    await this.store.saveRegistry(updatedEntries);
    this.setState({
      savedAccounts: updatedEntries,
      refreshing: false,
      updatedAt: nowIso(),
      status: "Saved account snapshots updated.",
      notice: "Saved account snapshots updated.",
    });
  }

  private async probeSavedAccountUsage(entry: AccountRegistryEntry) {
    const authKeychainKey = entry.authKeychainKey ?? normalizeAccountIdentity(entry);
    if (!authKeychainKey) {
      throw new Error(`Missing keychain key for ${entry.email}`);
    }

    const authBlob = await this.store.readAccountAuth(authKeychainKey || entry.id);
    const accessToken = authBlob?.tokens?.access_token?.trim();
    if (!accessToken) {
      throw new Error(`Missing access token for ${entry.email}`);
    }

    const payload = {
      model: OPENAI_PROBE_MODEL,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: "hi",
            },
          ],
        },
      ],
      stream: true,
      store: false,
      instructions: "You are a helpful assistant.",
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);

    try {
      const response = await fetch(OPENAI_PROBE_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: "text/event-stream",
          "OpenAI-Beta": "responses=experimental",
          Originator: "codex_cli_rs",
          Version: OPENAI_PROBE_VERSION,
          "User-Agent": `codex_cli_rs/${OPENAI_PROBE_VERSION}`,
          ...((entry.chatgptAccountId ?? "") !== ""
            ? { "chatgpt-account-id": entry.chatgptAccountId as string }
            : {}),
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });

      const snapshot = buildUsageSnapshotFromHeaders(response.headers);
      await response.body?.cancel().catch(() => {});

      if (!snapshot && !response.ok) {
        throw new Error(`Probe failed with HTTP ${response.status}`);
      }

      return snapshot;
    } finally {
      clearTimeout(timeout);
    }
  }

  private async handleLoginCompleted(notification: LoginCompletedNotification) {
    if (!notification.success) {
      this.loginFlow = {
        active: false,
        loginId: notification.loginId,
        authUrl: null,
        status: "Login failed",
        message: notification.error || "ChatGPT login failed.",
        error: notification.error || "ChatGPT login failed.",
      };
      this.setState({
        loginFlow: this.loginFlow,
        status: notification.error || "Login failed",
        error: notification.error || "Login failed",
      });
      return;
    }

    this.loginFlow = {
      active: false,
      loginId: notification.loginId,
      authUrl: null,
      status: "Login completed",
      message: "ChatGPT account signed in.",
      error: null,
    };

    const current = await this.loadDashboard();
    const authBlob = await this.store.readAuthBlob();

    if (authBlob && current.currentAccount) {
      const key =
        current.currentAccount.authKeychainKey ??
        current.currentAccount.chatgptAccountId ??
        current.currentAccount.email ??
        current.currentAccount.id;
      await this.store.saveAccountAuth(key || current.currentAccount.email, authBlob);
      await this.upsertRegistryEntry(current.currentAccount, authBlob);
    }

    this.setState({
      loginFlow: this.loginFlow,
      status: "Login completed.",
      error: null,
      loading: false,
      refreshing: false,
    });

    await this.reloadDashboard({ refreshSavedAccounts: true });
  }

  private async upsertRegistryEntry(currentAccount: AccountRegistryEntry, authBlob: AccountAuthBlob) {
    const registry = await this.store.loadRegistry();
    const identity = deriveAuthIdentity(authBlob);
    const key = identity.chatgptAccountId || currentAccount.chatgptAccountId || currentAccount.email;
    const entry: AccountRegistryEntry = {
      ...currentAccount,
      id: key,
      chatgptAccountId: key,
      maskedEmail: formatMaskedEmail(currentAccount.email),
      authKeychainKey: key,
      lastUsedAt: nowIso(),
      addedAt: currentAccount.addedAt || nowIso(),
    };

    const index = registry.findIndex((candidate) => compareEntryIdentity(candidate, entry));
    if (index >= 0) {
      registry[index] = {
        ...registry[index],
        ...entry,
      };
    } else {
      registry.unshift(entry);
    }
    await this.store.saveRegistry(registry);
  }

  async getDashboardState() {
    const state = await this.loadDashboard({ refreshSavedAccounts: true });
    return state;
  }

  async refreshCurrentAccount() {
    return await this.reloadDashboard({ refreshSavedAccounts: true });
  }

  async refreshSavedAccounts() {
    const registry = await this.store.loadRegistry();
    const preferences = await this.store.loadPreferences();
    const currentState = await this.loadCurrentAccount().catch(() => null);
    const currentIdentity = currentState?.authIdentity.chatgptAccountId || currentState?.authIdentity.email || "";
    const savedAccounts = registry
      .map((entry) => ({
        ...entry,
        maskedEmail: preferences.maskEmails ? entry.maskedEmail || formatMaskedEmail(entry.email) : entry.email,
      }))
      .filter((entry) => entry.chatgptAccountId !== currentIdentity && entry.email !== currentIdentity);
    await this.refreshSavedAccountSnapshots(savedAccounts, true);
    return await this.reloadDashboard({ refreshSavedAccounts: false });
  }

  async saveCurrentAccount(identity: AccountIdentity) {
    const authBlob = await this.store.readAuthBlob();
    if (!authBlob) {
      throw new Error("当前账号的 auth.json 不存在，无法保存。");
    }

    const dashboard = await this.loadDashboard({ refreshSavedAccounts: false });
    if (!dashboard.currentAccount) {
      throw new Error("没有可保存的当前账号。");
    }

    const key =
      identity.chatgptAccountId ||
      dashboard.currentAccount.chatgptAccountId ||
      dashboard.currentAccount.email ||
      dashboard.currentAccount.id;

    await this.store.saveAccountAuth(key, authBlob);
    await this.upsertRegistryEntry(
      {
        ...dashboard.currentAccount,
        authKeychainKey: key,
      },
      authBlob,
    );

    return await this.reloadDashboard({ refreshSavedAccounts: true });
  }

  async startAddAccount() {
    const response = await this.appServer.startChatgptLogin();
    if (response.type !== "chatgpt") {
      throw new Error("Codex 没有返回 ChatGPT 登录地址。");
    }

    this.loginFlow = {
      active: true,
      loginId: response.loginId,
      authUrl: response.authUrl,
      status: "Browser login opened",
      message: "请在浏览器中完成 ChatGPT 登录。",
      error: null,
    };

    Utils.openExternal(response.authUrl);
    this.setState({
      loginFlow: this.loginFlow,
      status: "浏览器登录已打开，请完成授权。",
      error: null,
    });

    return cloneJson(this.state);
  }

  async cancelAddAccount(payload: { loginId?: string | null }) {
    if (payload.loginId) {
      await this.appServer.cancelLogin(payload.loginId);
    } else if (this.loginFlow.loginId) {
      await this.appServer.cancelLogin(this.loginFlow.loginId);
    }

    this.loginFlow = {
      active: false,
      loginId: null,
      authUrl: null,
      status: "Login canceled",
      message: "已取消登录。",
      error: null,
    };
    this.setState({
      loginFlow: this.loginFlow,
      status: "已取消登录。",
      error: null,
    });
    return cloneJson(this.state);
  }

  async switchAccount(identity: AccountIdentity) {
    const registry = await this.store.loadRegistry();
    const entry = registry.find((candidate) => compareEntryIdentity(candidate, identity));
    if (!entry) {
      throw new Error("找不到要切换的账号。");
    }

    const authKeychainKey = entry.authKeychainKey ?? normalizeAccountIdentity(entry);
    if (!authKeychainKey) {
      throw new Error(`Keychain 中没有 ${entry.email} 的登录信息。`);
    }

    const authBlob = await this.store.readAccountAuth(authKeychainKey || entry.id);
    if (!authBlob) {
      throw new Error(`Keychain 中没有 ${entry.email} 的登录信息。`);
    }

    await this.store.writeAuthBlob(authBlob);

    const updated = registry.map((candidate) =>
      candidate.id === entry.id
        ? {
            ...candidate,
            lastUsedAt: nowIso(),
          }
        : candidate,
    );
    await this.store.saveRegistry(updated);
    await this.appServer.restart();
    const next = await this.reloadDashboard({ refreshSavedAccounts: true });

    return next;
  }

  async removeAccount(identity: AccountIdentity) {
    const registry = await this.store.loadRegistry();
    const entry = registry.find((candidate) => compareEntryIdentity(candidate, identity));
    if (!entry) {
      return await this.reloadDashboard({ refreshSavedAccounts: false });
    }

    const authKeychainKey = entry.authKeychainKey ?? normalizeAccountIdentity(entry);
    if (authKeychainKey) {
      await this.store.deleteAccountAuth(authKeychainKey || entry.id);
    }
    const nextRegistry = registry.filter((candidate) => candidate.id !== entry.id);
    await this.store.saveRegistry(nextRegistry);
    return await this.reloadDashboard({ refreshSavedAccounts: false });
  }

  async setMaskEmails(payload: { maskEmails: boolean }) {
    const preferences = await this.store.loadPreferences();
    preferences.maskEmails = payload.maskEmails;
    await this.store.savePreferences(preferences);
    return await this.reloadDashboard({ refreshSavedAccounts: false });
  }

  async openStatusPage() {
    Utils.openExternal(STATUS_PAGE_URL);
    return true;
  }

  async openSettings() {
    Utils.openPath(DATA_DIR);
    return true;
  }

  async quitApp() {
    Utils.quit();
    return true;
  }

  async reloadDashboard(options: { refreshSavedAccounts?: boolean } = {}) {
    return await this.loadDashboard({
      refreshSavedAccounts: options.refreshSavedAccounts ?? false,
      background: false,
    });
  }

  async bootstrap() {
    await this.store.ensureCacheDir();
    return await this.getDashboardState();
  }

  getRPCState() {
    return this.state;
  }
}

export function createController(rpc: {
  send: {
    dashboardStateUpdated: (state: DashboardState) => void;
  };
}) {
  const appServer = new CodexAppServerClient();
  const store = new LocalStore();
  return new DashboardController(appServer, store, rpc);
}

function asNumber(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}
