import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Utils } from "electrobun/bun";
import type {
  AccountRegistryEntry,
  AppPreferences,
  PlanType,
  UsageSnapshot,
} from "../shared/rpc";

const REGISTRY_VERSION = 1;
const KEYCHAIN_SERVICE = "com.bigo.cx-switch.account";
const CURRENT_AUTH_PATH = join(Utils.paths.home, ".codex", "auth.json");
const REGISTRY_PATH = join(Utils.paths.userData, "registry.json");
const PREFERENCES_PATH = join(Utils.paths.userData, "preferences.json");
const OPENAI_OAUTH_TOKEN_URL = "https://auth.openai.com/oauth/token";
const OPENAI_OAUTH_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const OPENAI_OAUTH_REFRESH_SCOPE = "openid profile email";

export const DEFAULT_PREFERENCES: AppPreferences = {
  maskEmails: true,
  refreshPolicy: "Refreshes saved accounts on open when snapshots are older than 60 seconds.",
  dataFolder: Utils.paths.userData,
};

type RegistryFile = {
  version: number;
  accounts: AccountRegistryEntry[];
};

export type AccountAuthBlob = {
  OPENAI_API_KEY?: string | null;
  auth_mode?: string | null;
  last_refresh?: string | null;
  tokens?: {
    access_token?: string | null;
    refresh_token?: string | null;
    id_token?: string | null;
    account_id?: string | null;
    [key: string]: unknown;
  } | null;
  [key: string]: unknown;
};

export type AccountIdentity = {
  email: string | null;
  chatgptAccountId: string | null;
};

type OpenAIAuthClaims = {
  email?: string;
  chatgpt_account_id?: string;
  chatgpt_plan_type?: string;
  [key: string]: unknown;
};

type OpenAIRefreshTokenResponse = {
  access_token?: string;
  id_token?: string;
  refresh_token?: string;
  token_type?: string;
  expires_in?: number;
  scope?: string;
  error?: string;
  error_description?: string;
};

type OpenAIRefreshTokenImportResult = {
  auth: AccountAuthBlob;
  identity: AccountIdentity;
  planType: PlanType | null;
};

async function ensureDirectory(path: string): Promise<void> {
  await mkdir(path, { recursive: true });
}

async function readJson<T>(path: string, fallback: T): Promise<T> {
  try {
    const raw = await readFile(path, "utf8");
    return JSON.parse(raw) as T;
  } catch (error) {
    const candidate = error as NodeJS.ErrnoException;
    if (candidate.code === "ENOENT") {
      return fallback;
    }
    throw error;
  }
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await ensureDirectory(dirname(path));
  const temporaryPath = `${path}.${crypto.randomUUID()}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await rename(temporaryPath, path);
}

export async function loadPreferences(): Promise<AppPreferences> {
  const stored = await readJson<Partial<AppPreferences>>(
    PREFERENCES_PATH,
    DEFAULT_PREFERENCES,
  );

  return {
    maskEmails:
      typeof stored.maskEmails === "boolean"
        ? stored.maskEmails
        : DEFAULT_PREFERENCES.maskEmails,
    refreshPolicy:
      typeof stored.refreshPolicy === "string" && stored.refreshPolicy
        ? stored.refreshPolicy
        : DEFAULT_PREFERENCES.refreshPolicy,
    dataFolder: DEFAULT_PREFERENCES.dataFolder,
  };
}

export async function savePreferences(
  preferences: Partial<AppPreferences>,
): Promise<AppPreferences> {
  const nextPreferences: AppPreferences = {
    ...DEFAULT_PREFERENCES,
    ...preferences,
    dataFolder: DEFAULT_PREFERENCES.dataFolder,
  };

  await writeJson(PREFERENCES_PATH, nextPreferences);
  return nextPreferences;
}

export async function loadRegistry(): Promise<AccountRegistryEntry[]> {
  const registry = await readJson<RegistryFile>(REGISTRY_PATH, {
    version: REGISTRY_VERSION,
    accounts: [],
  });

  return Array.isArray(registry.accounts) ? registry.accounts : [];
}

export async function saveRegistry(
  accounts: AccountRegistryEntry[],
): Promise<void> {
  await writeJson(REGISTRY_PATH, {
    version: REGISTRY_VERSION,
    accounts,
  } satisfies RegistryFile);
}

export async function readCurrentAuthBlob(): Promise<AccountAuthBlob | null> {
  return readJson<AccountAuthBlob | null>(CURRENT_AUTH_PATH, null);
}

export async function writeCurrentAuthBlob(auth: AccountAuthBlob): Promise<void> {
  await writeJson(CURRENT_AUTH_PATH, auth);
}

export function getDataFolder(): string {
  return Utils.paths.userData;
}

export function maskEmail(email: string): string {
  const [localPart, domainPart] = email.split("@");
  if (!localPart || !domainPart) {
    return email;
  }

  if (localPart.length <= 2) {
    return `${localPart[0] ?? ""}••••@${domainPart}`;
  }

  return `${localPart.slice(0, 1)}••••${localPart.slice(-1)}@${domainPart}`;
}

export function normalizePlanType(planType: unknown): PlanType | null {
  const value = typeof planType === "string" ? planType.trim().toLowerCase() : "";
  switch (value) {
    case "free":
    case "go":
    case "plus":
    case "pro":
    case "team":
    case "business":
    case "enterprise":
    case "edu":
    case "unknown":
      return value;
    default:
      return null;
  }
}

function decodeBase64Url(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    "=",
  );
  return Buffer.from(padded, "base64").toString("utf8");
}

export function decodeJwtPayload(
  token?: string | null,
): Record<string, unknown> | null {
  if (!token) {
    return null;
  }

  const payload = token.split(".")[1];
  if (!payload) {
    return null;
  }

  try {
    return JSON.parse(decodeBase64Url(payload)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function getOpenAIClaims(auth: AccountAuthBlob | null): OpenAIAuthClaims | null {
  const payload = decodeJwtPayload(auth?.tokens?.id_token ?? null);
  if (!payload) {
    return null;
  }

  const nested = payload["https://api.openai.com/auth"];
  if (!isRecord(nested)) {
    return null;
  }

  return nested as OpenAIAuthClaims;
}

export function deriveAccountIdentity(
  auth: AccountAuthBlob | null,
): AccountIdentity {
  const payload = decodeJwtPayload(auth?.tokens?.id_token ?? null);
  const claims = getOpenAIClaims(auth);
  return {
    email:
      typeof claims?.email === "string" && claims.email
        ? claims.email
        : typeof payload?.email === "string"
          ? payload.email
          : null,
    chatgptAccountId:
      typeof auth?.tokens?.account_id === "string" && auth.tokens.account_id
        ? auth.tokens.account_id
        : typeof claims?.chatgpt_account_id === "string" && claims.chatgpt_account_id
          ? claims.chatgpt_account_id
        : null,
  };
}

export function sanitizeRefreshTokenInput(raw: string): string {
  return raw
    .trim()
    .replace(/^["'`]+/, "")
    .replace(/["'`;]+$/, "")
    .trim();
}

export async function importRefreshToken(
  rawRefreshToken: string,
): Promise<OpenAIRefreshTokenImportResult> {
  const refreshToken = sanitizeRefreshTokenInput(rawRefreshToken);
  if (!refreshToken) {
    throw new Error("Refresh token is required.");
  }

  const response = await fetch(OPENAI_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
      Origin: "https://chatgpt.com",
      Referer: "https://chatgpt.com/",
      "User-Agent": "CX Switch/1.0",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: OPENAI_OAUTH_CLIENT_ID,
      refresh_token: refreshToken,
      scope: OPENAI_OAUTH_REFRESH_SCOPE,
    }),
  });

  const responseText = await response.text();
  let parsed: OpenAIRefreshTokenResponse | null = null;
  try {
    parsed = JSON.parse(responseText) as OpenAIRefreshTokenResponse;
  } catch {
    parsed = null;
  }

  if (!response.ok) {
    const errorMessage =
      (typeof parsed?.error_description === "string" && parsed.error_description) ||
      (typeof parsed?.error === "string" && parsed.error) ||
      responseText.trim() ||
      `Refresh token exchange failed with status ${response.status}.`;
    throw new Error(errorMessage);
  }

  const accessToken = parsed?.access_token?.trim() ?? "";
  const idToken = parsed?.id_token?.trim() ?? "";
  const nextRefreshToken = parsed?.refresh_token?.trim() || refreshToken;

  if (!accessToken || !idToken) {
    throw new Error("OpenAI did not return a complete token bundle.");
  }

  const payload = decodeJwtPayload(idToken);
  const claims = getOpenAIClaims({ tokens: { id_token: idToken } });
  const email =
    (typeof claims?.email === "string" && claims.email) ||
    (typeof payload?.email === "string" && payload.email) ||
    null;
  const chatgptAccountId =
    (typeof claims?.chatgpt_account_id === "string" && claims.chatgpt_account_id) ||
    (typeof payload?.sub === "string" && payload.sub) ||
    null;

  const auth: AccountAuthBlob = {
    auth_mode: "oauth",
    last_refresh: new Date().toISOString(),
    tokens: {
      access_token: accessToken,
      refresh_token: nextRefreshToken,
      id_token: idToken,
      account_id: chatgptAccountId,
    },
  };

  return {
    auth,
    identity: {
      email,
      chatgptAccountId,
    },
    planType: normalizePlanType(claims?.chatgpt_plan_type ?? null),
  };
}

export function findMatchingAccount(
  accounts: AccountRegistryEntry[],
  identity: AccountIdentity,
): AccountRegistryEntry | null {
  if (identity.chatgptAccountId) {
    const byId = accounts.find(
      (account) => account.chatgptAccountId === identity.chatgptAccountId,
    );
    if (byId) {
      return byId;
    }
  }

  if (identity.email) {
    const normalizedEmail = identity.email.toLowerCase();
    return (
      accounts.find((account) => account.email.toLowerCase() === normalizedEmail) ??
      null
    );
  }

  return null;
}

function runSecurity(args: string[]): string {
  const result = Bun.spawnSync({
    cmd: ["security", ...args],
    stdout: "pipe",
    stderr: "pipe",
  });

  if (result.exitCode !== 0) {
    const message = result.stderr.toString().trim();
    throw new Error(message || "Keychain operation failed.");
  }

  return result.stdout.toString().trim();
}

export function saveKeychainAuth(
  accountId: string,
  auth: AccountAuthBlob,
): void {
  const encoded = Buffer.from(JSON.stringify(auth), "utf8").toString("base64");
  runSecurity([
    "add-generic-password",
    "-a",
    accountId,
    "-s",
    KEYCHAIN_SERVICE,
    "-U",
    "-w",
    encoded,
  ]);
}

export function loadKeychainAuth(accountId: string): AccountAuthBlob | null {
  try {
    const encoded = runSecurity([
      "find-generic-password",
      "-a",
      accountId,
      "-s",
      KEYCHAIN_SERVICE,
      "-w",
    ]);

    return JSON.parse(
      Buffer.from(encoded, "base64").toString("utf8"),
    ) as AccountAuthBlob;
  } catch (error) {
    const message =
      error instanceof Error ? error.message.toLowerCase() : String(error);
    if (message.includes("could not be found")) {
      return null;
    }
    throw error;
  }
}

export function deleteKeychainAuth(accountId: string): void {
  try {
    runSecurity([
      "delete-generic-password",
      "-a",
      accountId,
      "-s",
      KEYCHAIN_SERVICE,
    ]);
  } catch (error) {
    const message =
      error instanceof Error ? error.message.toLowerCase() : String(error);
    if (!message.includes("could not be found")) {
      throw error;
    }
  }
}

export async function upsertAccountRegistryEntry(params: {
  auth: AccountAuthBlob;
  email: string;
  planType: PlanType | null;
  chatgptAccountId: string | null;
  usageSnapshot: UsageSnapshot | null;
}): Promise<AccountRegistryEntry> {
  const accounts = await loadRegistry();
  const now = new Date().toISOString();
  const existing = findMatchingAccount(accounts, {
    email: params.email,
    chatgptAccountId: params.chatgptAccountId,
  });

  const nextEntry: AccountRegistryEntry = {
    id: existing?.id ?? crypto.randomUUID(),
    email: params.email,
    maskedEmail: maskEmail(params.email),
    planType: params.planType,
    chatgptAccountId: params.chatgptAccountId,
    addedAt: existing?.addedAt ?? now,
    lastUsedAt: now,
    usageSnapshot: params.usageSnapshot ?? existing?.usageSnapshot ?? null,
    authKeychainKey: existing?.authKeychainKey ?? existing?.id ?? undefined,
    usageError: null,
  };

  saveKeychainAuth(nextEntry.id, params.auth);

  const nextAccounts = existing
    ? accounts.map((account) =>
        account.id === existing.id ? nextEntry : account,
      )
    : [...accounts, nextEntry];
  await saveRegistry(nextAccounts);

  return nextEntry;
}

export async function updateRegistryEntry(
  accountId: string,
  updater: (entry: AccountRegistryEntry) => AccountRegistryEntry,
): Promise<AccountRegistryEntry | null> {
  const accounts = await loadRegistry();
  const current = accounts.find((entry) => entry.id === accountId);
  if (!current) {
    return null;
  }

  const nextEntry = updater(current);
  await saveRegistry(
    accounts.map((entry) => (entry.id === accountId ? nextEntry : entry)),
  );
  return nextEntry;
}

export async function deleteRegistryEntry(accountId: string): Promise<void> {
  const accounts = await loadRegistry();
  await saveRegistry(accounts.filter((entry) => entry.id !== accountId));
  deleteKeychainAuth(accountId);
}

export async function sortRegistryByLastUsed(): Promise<AccountRegistryEntry[]> {
  const accounts = await loadRegistry();
  return [...accounts].sort((left, right) => {
    const leftTime = Date.parse(left.lastUsedAt ?? left.addedAt);
    const rightTime = Date.parse(right.lastUsedAt ?? right.addedAt);
    return rightTime - leftTime;
  });
}

export function withAccountSnapshot(
  entry: AccountRegistryEntry,
  usageSnapshot: UsageSnapshot | null,
  usageError: string | null,
): AccountRegistryEntry {
  return {
    ...entry,
    usageSnapshot: usageSnapshot ?? entry.usageSnapshot ?? null,
    usageError,
  };
}
