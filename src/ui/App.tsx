import { useEffect, useMemo, useRef, useState, type RefObject } from "react";
import { Electroview } from "electrobun/view";

const APP_NAME = "CX Switch";
let onDashboardStateMessage: ((state: unknown) => void) | null = null;

const rpc = Electroview.defineRPC<any>({
  handlers: {
    requests: {},
    messages: {
      dashboardStateUpdated: (state: unknown) => {
        onDashboardStateMessage?.(state);
      },
    },
  },
});

const electrobun = new Electroview({ rpc });

type PlanType = string;

type UsageWindow = {
  label?: string;
  title?: string;
  name?: string;
  windowDurationMins?: number | null;
  usedPercent?: number | null;
  resetsAt?: number | string | null;
  resetText?: string | null;
  resetsIn?: string | null;
};

type UsageSnapshot = {
  primary?: UsageWindow | null;
  secondary?: UsageWindow | null;
  windows?: UsageWindow[] | null;
  entries?: UsageWindow[] | null;
  rateLimits?: {
    primary?: UsageWindow | null;
    secondary?: UsageWindow | null;
  } | null;
  updatedAt?: string | number | null;
  lastUpdatedAt?: string | number | null;
};

type AccountRegistryEntry = {
  id?: string;
  email?: string;
  maskedEmail?: string;
  planType?: PlanType | null;
  chatgptAccountId?: string | null;
  addedAt?: string | number | null;
  lastUsedAt?: string | number | null;
  usageSnapshot?: UsageSnapshot | null;
  rateLimits?: UsageSnapshot | null;
  active?: boolean;
  isCurrent?: boolean;
  current?: boolean;
};

type AppPreferences = {
  maskEmails?: boolean;
  refreshPolicy?: string;
  dataFolder?: string;
};

type LoginFlowState = {
  active?: boolean;
  loginId?: string | null;
  authUrl?: string | null;
  status?: string | null;
  message?: string | null;
  error?: string | null;
  phase?: string | null;
};

type DashboardState = {
  appName?: string;
  updatedAt?: string | number | null;
  currentAccount?: AccountRegistryEntry | null;
  savedAccounts?: AccountRegistryEntry[] | null;
  accounts?: AccountRegistryEntry[] | null;
  registry?: AccountRegistryEntry[] | null;
  preferences?: AppPreferences | null;
  loginFlow?: LoginFlowState | null;
  error?: string | null;
  status?: string | null;
  notice?: string | null;
  loading?: boolean | null;
  isRefreshing?: boolean | null;
};

type RpcRequestName =
  | "getDashboardState"
  | "refreshCurrentAccount"
  | "refreshSavedAccounts"
  | "saveCurrentAccount"
  | "importRefreshToken"
  | "readClipboardText"
  | "startAddAccount"
  | "cancelAddAccount"
  | "switchAccount"
  | "removeAccount"
  | "setMaskEmails"
  | "openStatusPage"
  | "openSettings"
  | "quitApp";

type RpcBridge = {
  request: Record<RpcRequestName, (params?: Record<string, unknown>) => Promise<unknown>>;
};

type WindowModel = {
  id: string;
  label: string;
  remainingPercent: number;
  resetsText: string;
  durationMins: number;
};

type AccountModel = {
  id: string;
  email: string;
  displayEmail: string;
  planType: string;
  chatgptAccountId: string;
  usage: {
    fiveHours: WindowModel;
    weekly: WindowModel;
  };
  source: AccountRegistryEntry;
  isCurrent: boolean;
};

type DashboardModel = {
  appName: string;
  updatedText: string;
  loading: boolean;
  refreshing: boolean;
  error: string | null;
  status: string | null;
  currentAccount: AccountModel | null;
  savedAccounts: AccountModel[];
  preferences: AppPreferences;
  loginFlow: LoginFlowState | null;
  canSaveCurrentAccount: boolean;
};

const rpcClient = electrobun.rpc as RpcBridge | undefined;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function asText(value: unknown, fallback = ""): string {
  if (typeof value === "string" && value.trim()) {
    return value;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }

  return fallback;
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function clampPercent(value: unknown): number {
  const parsed = asNumber(value) ?? 0;
  return Math.max(0, Math.min(100, Math.round(parsed)));
}

function toMillis(value: number): number {
  return value < 1_000_000_000_000 ? value * 1000 : value;
}

function formatRelativeTime(value: string | number | null | undefined): string {
  if (value == null) {
    return "just now";
  }

  const raw = typeof value === "number" ? toMillis(value) : Date.parse(value);
  if (!Number.isFinite(raw)) {
    return "just now";
  }

  const diff = Date.now() - raw;
  if (diff < 15_000) {
    return "just now";
  }

  const minutes = Math.round(diff / 60_000);
  if (minutes < 60) {
    return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  }

  const hours = Math.round(minutes / 60);
  if (hours < 24) {
    return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  }

  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

function formatCountdown(value: string | number | null | undefined): string {
  if (value == null) {
    return "Reset soon";
  }

  const raw = typeof value === "number" ? toMillis(value) : Date.parse(value);
  if (!Number.isFinite(raw)) {
    return "Reset soon";
  }

  const diff = raw - Date.now();
  if (diff <= 0) {
    return "Resets soon";
  }

  const minutes = Math.round(diff / 60_000);
  if (minutes < 60) {
    return `Resets in ${minutes}m`;
  }

  const hours = Math.floor(minutes / 60);
  const remaining = minutes % 60;
  if (hours < 24) {
    return remaining > 0 ? `Resets in ${hours}h ${remaining}m` : `Resets in ${hours}h`;
  }

  const days = Math.floor(hours / 24);
  const dayHours = hours % 24;
  return dayHours > 0 ? `Resets in ${days}d ${dayHours}h` : `Resets in ${days}d`;
}

function formatWindowLabel(window: UsageWindow | null | undefined): string {
  if (!window) {
    return "Usage";
  }

  const duration = window.windowDurationMins;
  if (duration === 300) {
    return "5 Hours";
  }
  if (duration === 10_080) {
    return "Weekly";
  }

  const label = asText(window.label || window.title || window.name);
  if (label) {
    return label;
  }

  if (duration != null) {
    if (duration < 60) {
      return `${duration}m`;
    }

    const hours = Math.round(duration / 60);
    if (hours % 24 === 0) {
      return `${hours / 24}d`;
    }

    return `${hours}h`;
  }

  return "Usage";
}

function pickWindow(
  candidates: Array<UsageWindow | null | undefined>,
  durationMins: number,
): UsageWindow | null {
  return (
    candidates.find((candidate) => candidate?.windowDurationMins === durationMins) ??
    null
  );
}

function resetTimestampMs(window: UsageWindow | null | undefined): number | null {
  if (!window) {
    return null;
  }

  const value = window.resetsAt ?? window.resetText;
  if (typeof value === "number" && Number.isFinite(value)) {
    return value < 1_000_000_000_000 ? value * 1000 : value;
  }

  if (typeof value === "string" && value.trim()) {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function resolveUsageWindows(
  candidates: Array<UsageWindow | null | undefined>,
): {
  fiveHours: UsageWindow | null;
  weekly: UsageWindow | null;
} {
  const fiveHourExact = pickWindow(candidates, 300);
  const weeklyExact = pickWindow(candidates, 10_080);

  if (fiveHourExact || weeklyExact) {
    return {
      fiveHours: fiveHourExact ?? inferFiveHourWindow(candidates, weeklyExact),
      weekly: weeklyExact ?? inferWeeklyWindow(candidates, fiveHourExact),
    };
  }

  const orderedByReset = candidates
    .filter((candidate): candidate is UsageWindow => Boolean(candidate))
    .sort((left, right) => {
      const leftReset = resetTimestampMs(left) ?? Number.MAX_SAFE_INTEGER;
      const rightReset = resetTimestampMs(right) ?? Number.MAX_SAFE_INTEGER;
      return leftReset - rightReset;
    });

  if (orderedByReset.length >= 2) {
    return {
      fiveHours: orderedByReset[0] ?? null,
      weekly: orderedByReset[orderedByReset.length - 1] ?? null,
    };
  }

  return {
    fiveHours: candidates.find((candidate): candidate is UsageWindow => Boolean(candidate)) ?? null,
    weekly:
      candidates
        .slice()
        .reverse()
        .find((candidate): candidate is UsageWindow => Boolean(candidate)) ?? null,
  };
}

function inferFiveHourWindow(
  candidates: Array<UsageWindow | null | undefined>,
  exclude: UsageWindow | null,
): UsageWindow | null {
  const filtered = candidates.filter(
    (candidate): candidate is UsageWindow => Boolean(candidate) && candidate !== exclude,
  );
  if (filtered.length === 0) {
    return null;
  }

  const ordered = filtered.sort((left, right) => {
    const leftReset = resetTimestampMs(left) ?? Number.MAX_SAFE_INTEGER;
    const rightReset = resetTimestampMs(right) ?? Number.MAX_SAFE_INTEGER;
    return leftReset - rightReset;
  });

  return ordered[0] ?? filtered[0] ?? null;
}

function inferWeeklyWindow(
  candidates: Array<UsageWindow | null | undefined>,
  exclude: UsageWindow | null,
): UsageWindow | null {
  const filtered = candidates.filter(
    (candidate): candidate is UsageWindow => Boolean(candidate) && candidate !== exclude,
  );
  if (filtered.length === 0) {
    return null;
  }

  const ordered = filtered.sort((left, right) => {
    const leftReset = resetTimestampMs(left) ?? Number.MAX_SAFE_INTEGER;
    const rightReset = resetTimestampMs(right) ?? Number.MAX_SAFE_INTEGER;
    return leftReset - rightReset;
  });

  return ordered.at(-1) ?? filtered.at(-1) ?? null;
}

function normalizeWindow(
  window: UsageWindow | null | undefined,
  fallbackLabel: string,
  fallbackDuration: number,
): WindowModel {
  const usedPercent = clampPercent(window?.usedPercent);
  const remainingPercent = Math.max(0, Math.min(100, 100 - usedPercent));
  const resetsText = formatCountdown(window?.resetsAt ?? window?.resetsIn ?? window?.resetText);

  return {
    id: `${fallbackLabel}-${fallbackDuration}`,
    label: fallbackLabel,
    remainingPercent,
    resetsText,
    durationMins: fallbackDuration,
  };
}

function buildUsageModel(snapshot: UsageSnapshot | null | undefined): {
  fiveHours: WindowModel;
  weekly: WindowModel;
} {
  const rawWindows = [
    snapshot?.primary ?? null,
    snapshot?.secondary ?? null,
    ...(snapshot?.windows ?? []),
    ...(snapshot?.entries ?? []),
    snapshot?.rateLimits?.primary ?? null,
    snapshot?.rateLimits?.secondary ?? null,
  ];

  const resolved = resolveUsageWindows(rawWindows);

  return {
    fiveHours: normalizeWindow(resolved.fiveHours, "5 Hours", 300),
    weekly: normalizeWindow(resolved.weekly, "Weekly", 10_080),
  };
}

function normalizeAccount(
  account: AccountRegistryEntry | null | undefined,
  currentAccountId: string | null | undefined,
  maskEmails: boolean,
): AccountModel | null {
  if (!account) {
    return null;
  }

  const email = asText(account.email || account.maskedEmail);
  if (!email) {
    return null;
  }

  const usageSnapshot = account.usageSnapshot ?? account.rateLimits ?? null;
  const usage = buildUsageModel(usageSnapshot);
  const chatgptAccountId = asText(account.chatgptAccountId, email);
  const id = asText(account.id, chatgptAccountId || email);
  const isCurrent =
    Boolean(account.isCurrent || account.current || account.active) ||
    (currentAccountId ? currentAccountId === chatgptAccountId || currentAccountId === email : false);

  return {
    id,
    email,
    displayEmail: maskEmails ? account.maskedEmail || maskEmail(email) : email,
    planType: asText(account.planType, "unknown"),
    chatgptAccountId,
    usage,
    source: account,
    isCurrent,
  };
}

function extractState(candidate: unknown): DashboardState | null {
  if (!isRecord(candidate)) {
    return null;
  }

  if (
    "currentAccount" in candidate ||
    "savedAccounts" in candidate ||
    "accounts" in candidate ||
    "registry" in candidate ||
    "preferences" in candidate ||
    "loginFlow" in candidate
  ) {
    return candidate as DashboardState;
  }

  for (const key of ["dashboardState", "state", "result", "data"]) {
    const nested = candidate[key];
    if (isRecord(nested)) {
      const extracted = extractState(nested);
      if (extracted) {
        return extracted;
      }
    }
  }

  return null;
}

function hasIdentityMatch(left: AccountRegistryEntry | null | undefined, right: AccountModel | null) {
  if (!left || !right) {
    return false;
  }

  return Boolean(
    (left.chatgptAccountId && left.chatgptAccountId === right.chatgptAccountId) ||
      (left.email && left.email === right.email) ||
      (left.maskedEmail && left.maskedEmail === right.displayEmail) ||
      (left.id && left.id === right.id),
  );
}

function buildDashboardModel(state: DashboardState | null, fallbackLoading = false): DashboardModel {
  const preferences = state?.preferences ?? {};
  const maskEmails = preferences.maskEmails ?? true;
  const currentAccountRaw = state?.currentAccount ?? null;
  const currentAccount = normalizeAccount(
    currentAccountRaw,
    currentAccountRaw?.chatgptAccountId,
    maskEmails,
  );
  const listSource = state?.savedAccounts ?? state?.accounts ?? state?.registry ?? [];
  const savedAccounts = (listSource ?? [])
    .map((account) => normalizeAccount(account, currentAccount?.chatgptAccountId, maskEmails))
    .filter((account): account is AccountModel => Boolean(account))
    .filter((account) => !hasIdentityMatch(currentAccountRaw, account))
    .sort((left, right) => {
      if (left.isCurrent !== right.isCurrent) {
        return Number(right.isCurrent) - Number(left.isCurrent);
      }
      return left.email.localeCompare(right.email);
    });

  const canSaveCurrentAccount =
    Boolean(currentAccountRaw) &&
    !savedAccounts.some((account) => hasIdentityMatch(currentAccountRaw, account));

  return {
    appName: asText(state?.appName, APP_NAME),
    updatedText: formatRelativeTime(state?.updatedAt ?? state?.currentAccount?.lastUsedAt ?? null),
    loading: Boolean(state?.loading ?? fallbackLoading),
    refreshing: Boolean(state?.isRefreshing),
    error: asText(state?.error, ""),
    status: asText(state?.status ?? state?.notice, ""),
    currentAccount,
    savedAccounts,
    preferences: {
      maskEmails,
      refreshPolicy: asText(preferences.refreshPolicy, "Refreshes saved accounts on open."),
      dataFolder: asText(preferences.dataFolder, ""),
    },
    loginFlow: state?.loginFlow ?? null,
    canSaveCurrentAccount,
  };
}

function getEmptyDashboard(): DashboardModel {
  return buildDashboardModel(
    {
      appName: APP_NAME,
      loading: true,
      preferences: { maskEmails: true },
      savedAccounts: [],
      currentAccount: null,
    },
    true,
  );
}

function identityFromAccount(account: AccountModel) {
  return {
    id: account.id,
    email: account.email,
    maskedEmail: account.displayEmail,
    chatgptAccountId: account.chatgptAccountId,
  };
}

function sectionTitleCount(count: number) {
  return count > 0 ? `Switch Account ${count}` : "Switch Account";
}

function appPlanLabel(planType: string | null | undefined) {
  if (!planType) {
    return "UNKNOWN";
  }

  return planType.toUpperCase();
}

function maskEmail(email: string) {
  const [localPart = "", domainPart = ""] = email.split("@");
  if (!domainPart) {
    return email;
  }

  if (localPart.length <= 2) {
    return `${localPart[0] ?? ""}••••@${domainPart}`;
  }

  return `${localPart.slice(0, 1)}••••${localPart.slice(-1)}@${domainPart}`;
}

function displayEmail(email: string, mask = true) {
  return mask ? maskEmail(email) : email;
}

function UsageBar({
  label,
  percent,
  resetsText,
  compact = false,
}: {
  label: string;
  percent: number;
  resetsText: string;
  compact?: boolean;
}) {
  return (
    <div className={`usage-block${compact ? " usage-block-compact" : ""}`}>
      <div className="usage-head">
        <span className="usage-label">{label}</span>
        <span className="usage-percent">{percent}%</span>
      </div>
      <div className="usage-track" aria-hidden="true">
        <div className="usage-fill" style={{ width: `${percent}%` }} />
      </div>
      <p className="usage-reset">{resetsText}</p>
    </div>
  );
}

function AccountUsage({
  usage,
  compact = false,
}: {
  usage: AccountModel["usage"];
  compact?: boolean;
}) {
  return (
    <div className={`usage-stack${compact ? " usage-stack-compact" : ""}`}>
      <UsageBar
        label={usage.fiveHours.label}
        percent={usage.fiveHours.remainingPercent}
        resetsText={usage.fiveHours.resetsText}
        compact={compact}
      />
      <UsageBar
        label={usage.weekly.label}
        percent={usage.weekly.remainingPercent}
        resetsText={usage.weekly.resetsText}
        compact={compact}
      />
    </div>
  );
}

function AccountCard({
  account,
  isCompact = false,
  showFullEmails,
  onSwitch,
  onRemove,
}: {
  account: AccountModel;
  isCompact?: boolean;
  showFullEmails: boolean;
  onSwitch: (account: AccountModel) => void;
  onRemove: (account: AccountModel) => void;
}) {
  return (
    <article className={`account-card${account.isCurrent ? " account-card-current" : ""}${isCompact ? " account-card-compact" : ""}`}>
      <div className="account-topline">
        <div className="account-email-wrap">
          <div className="account-email">{showFullEmails ? account.email : account.displayEmail}</div>
          {account.isCurrent ? <span className="account-current-pill">Current</span> : null}
        </div>
        <div className="account-plan">{appPlanLabel(account.planType)}</div>
      </div>
      <AccountUsage usage={account.usage} compact />
      <div className="account-actions">
        <button
          className="inline-button inline-button-primary"
          type="button"
          onClick={() => onSwitch(account)}
          disabled={account.isCurrent}
        >
          {account.isCurrent ? "Active" : "Switch"}
        </button>
        <button
          className="inline-button"
          type="button"
          onClick={() => onRemove(account)}
        >
          Remove
        </button>
      </div>
    </article>
  );
}

function FooterAction({
  title,
  subtitle,
  onClick,
  active = false,
  disabled = false,
  danger = false,
}: {
  title: string;
  subtitle: string;
  onClick: () => void;
  active?: boolean;
  disabled?: boolean;
  danger?: boolean;
}) {
  return (
    <button
      className={`footer-action${active ? " footer-action-active" : ""}${danger ? " footer-action-danger" : ""}`}
      type="button"
      onClick={onClick}
      disabled={disabled}
    >
      <span className="footer-action-title">{title}</span>
      <span className="footer-action-subtitle">{subtitle}</span>
    </button>
  );
}

function NoticeBanner({
  kind,
  title,
  detail,
  actionLabel,
  onAction,
}: {
  kind: "info" | "error" | "login" | "loading";
  title: string;
  detail: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <div className={`notice-banner notice-${kind}`}>
      <div className="notice-copy">
        <strong>{title}</strong>
        <span>{detail}</span>
      </div>
      {actionLabel && onAction ? (
        <button className="inline-button inline-button-secondary" type="button" onClick={onAction}>
          {actionLabel}
        </button>
      ) : null}
    </div>
  );
}

function RefreshTokenImportPanel({
  value,
  onChange,
  onImport,
  onCancel,
  onPasteShortcut,
  onPasteText,
  inputRef,
  busy = false,
}: {
  value: string;
  onChange: (value: string) => void;
  onImport: () => void;
  onCancel: () => void;
  onPasteShortcut: () => void;
  onPasteText: (text: string) => void;
  inputRef: RefObject<HTMLTextAreaElement | null>;
  busy?: boolean;
}) {
  return (
    <div className="import-panel">
      <div className="notice-copy">
        <strong>Import Refresh Token</strong>
        <span>Paste the OpenAI refresh token here. We will exchange it for a full auth bundle.</span>
      </div>
      <textarea
        ref={inputRef}
        className="import-input"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={(event) => {
          if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "v") {
            event.preventDefault();
            event.stopPropagation();
            onPasteShortcut();
          }

          if (event.key === "Escape") {
            event.preventDefault();
            onCancel();
          }

          if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "enter") {
            event.preventDefault();
            onImport();
          }
        }}
        onPaste={(event) => {
          event.preventDefault();
          onPasteText(event.clipboardData.getData("text"));
        }}
        placeholder="Paste refresh_token here"
        rows={3}
        spellCheck={false}
        autoCapitalize="off"
        autoCorrect="off"
      />
      <div className="import-actions">
        <button
          className="inline-button inline-button-primary"
          type="button"
          onClick={onImport}
          disabled={busy || !value.trim()}
        >
          Import
        </button>
        <button className="inline-button" type="button" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
      </div>
    </div>
  );
}

export function App() {
  const [dashboard, setDashboard] = useState<DashboardModel>(() => getEmptyDashboard());
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [initialLoadError, setInitialLoadError] = useState<string | null>(null);
  const [showFullEmails, setShowFullEmails] = useState(true);
  const [showRefreshImport, setShowRefreshImport] = useState(false);
  const [refreshTokenDraft, setRefreshTokenDraft] = useState("");
  const refreshImportRef = useRef<HTMLTextAreaElement | null>(null);

  const currentAccount = dashboard.currentAccount;
  const savedAccounts = dashboard.savedAccounts;
  const isLoading = dashboard.loading && !currentAccount && savedAccounts.length === 0;
  const isLoginActive = Boolean(dashboard.loginFlow?.active || dashboard.loginFlow?.loginId);

  const showEmail = showFullEmails;

  useEffect(() => {
    onDashboardStateMessage = (state: unknown) => {
      const next = buildDashboardModel(extractState(state), false);
      setDashboard(next);
      setInitialLoadError(null);
    };

    return () => {
      onDashboardStateMessage = null;
    };
  }, []);

  useEffect(() => {
    if (!showRefreshImport) {
      return;
    }

    const timer = window.setTimeout(() => {
      refreshImportRef.current?.focus();
      refreshImportRef.current?.select();
    }, 0);

    return () => window.clearTimeout(timer);
  }, [showRefreshImport]);

  useEffect(() => {
    if (!showRefreshImport) {
      return;
    }

    const onWindowKeyDown = async (event: KeyboardEvent) => {
      const key = event.key.toLowerCase();
      if ((event.metaKey || event.ctrlKey) && key === "v") {
        event.preventDefault();
        event.stopPropagation();
        await pasteRefreshTokenFromClipboard();
      }

      if ((event.metaKey || event.ctrlKey) && key === "enter") {
        event.preventDefault();
        event.stopPropagation();
        await runAction("importRefreshToken", { refreshToken: refreshTokenDraft });
      }

      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        if (busyAction !== "importRefreshToken") {
          setShowRefreshImport(false);
          setRefreshTokenDraft("");
        }
      }
    };

    window.addEventListener("keydown", onWindowKeyDown, true);
    return () => window.removeEventListener("keydown", onWindowKeyDown, true);
  }, [showRefreshImport, refreshTokenDraft, busyAction]);

  const allAccountCount = useMemo(() => {
    const currentKey = currentAccount ? currentAccount.id : null;
    const unique = new Set<string>();

    if (currentAccount) {
      unique.add(currentKey || currentAccount.email);
    }

    for (const account of savedAccounts) {
      unique.add(account.id || account.email);
    }

    return unique.size;
  }, [currentAccount, savedAccounts]);

  async function syncDashboard() {
    if (!rpcClient) {
      throw new Error("Electrobun RPC bridge is unavailable.");
    }

    const response = await rpcClient.request.getDashboardState({});
    const state = extractState(response);
    const next = buildDashboardModel(state, false);
    setDashboard(next);
    setInitialLoadError(null);
    return next;
  }

  async function runAction(name: RpcRequestName, params: Record<string, unknown> = {}) {
    if (!rpcClient) {
      throw new Error("Electrobun RPC bridge is unavailable.");
    }

    setBusyAction(name);

    try {
      const response = await rpcClient.request[name](params);
      const state = extractState(response);
      if (name === "importRefreshToken") {
        setRefreshTokenDraft("");
        setShowRefreshImport(false);
      }
      if (state) {
        const next = buildDashboardModel(state, false);
        setDashboard(next);
        setInitialLoadError(null);
        return next;
      }

      if (name === "openStatusPage" || name === "openSettings" || name === "quitApp") {
        return null;
      }

      return syncDashboard();
    } finally {
      setBusyAction(null);
    }
  }

  async function pasteRefreshTokenFromClipboard() {
    if (!rpcClient) {
      return;
    }

    const clipboardText = await rpcClient.request.readClipboardText({});
    const text = typeof clipboardText === "string" ? clipboardText : "";
    if (!text.trim()) {
      return;
    }

    setRefreshTokenDraft((current) => {
      const next = current ? `${current}\n${text}` : text;
      return next.trim();
    });
  }

  async function handleInitialLoad() {
    setDashboard((current) => ({ ...current, loading: true }));

    try {
      await syncDashboard();
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unable to load CX Switch.";
      setInitialLoadError(message);
      setDashboard((current) => ({
        ...current,
        loading: false,
        error: message,
      }));
    }
  }

  useEffect(() => {
    void handleInitialLoad();
  }, []);

  const showNotice = dashboard.error || initialLoadError || dashboard.status;

  const settingsSummary = dashboard.preferences.dataFolder
    ? `Data folder: ${dashboard.preferences.dataFolder}`
    : dashboard.preferences.refreshPolicy || "Refreshes saved accounts on open.";

  return (
    <div className="app-shell">
      <div className="orb orb-left" aria-hidden="true" />
      <div className="orb orb-right" aria-hidden="true" />

      <header className="shell-header">
        <div>
          <p className="eyebrow">Desktop tray popup</p>
          <h1>{dashboard.appName}</h1>
        </div>
        <div className="header-meta">
          <span className="header-updated">{dashboard.updatedText}</span>
          <button
            className="round-button"
            type="button"
            onClick={() => void runAction("refreshCurrentAccount")}
            disabled={busyAction === "refreshCurrentAccount" || dashboard.loading}
            aria-label="Refresh current account"
          >
            Refresh
          </button>
        </div>
      </header>

      {isLoading ? (
        <section className="panel panel-loading" aria-busy="true">
          <div className="skeleton-line skeleton-title" />
          <div className="skeleton-line skeleton-subtitle" />
          <div className="skeleton-stack">
            <div className="skeleton-line" />
            <div className="skeleton-line" />
          </div>
          <div className="skeleton-rows">
            <div className="skeleton-row" />
            <div className="skeleton-row" />
            <div className="skeleton-row" />
          </div>
        </section>
      ) : null}

      {!isLoading && currentAccount ? (
        <section className="panel current-panel">
          <div className="current-topline">
            <div>
              <p className="section-label">Current Account</p>
              <div className="current-email">{showEmail ? currentAccount.email : currentAccount.displayEmail}</div>
            </div>
            <div className="current-side">
              <span className="plan-pill">{appPlanLabel(currentAccount.planType)}</span>
              <button
                className="round-button round-button-ghost"
                type="button"
                onClick={() => void runAction("refreshCurrentAccount")}
                disabled={busyAction === "refreshCurrentAccount"}
              >
                Refresh
              </button>
            </div>
          </div>

          <AccountUsage usage={currentAccount.usage} compact />

          {dashboard.canSaveCurrentAccount ? (
            <div className="save-current">
              <div>
                <strong>Current account is not in the saved registry.</strong>
                <span>Save it once so switching stays one tap away.</span>
              </div>
              <button
                className="inline-button inline-button-primary"
                type="button"
                onClick={() => void runAction("saveCurrentAccount", identityFromAccount(currentAccount))}
                disabled={busyAction === "saveCurrentAccount"}
              >
                Save Current Account
              </button>
            </div>
          ) : null}
        </section>
      ) : null}

      {showNotice ? (
        <NoticeBanner
          kind={initialLoadError || dashboard.error ? "error" : isLoginActive ? "login" : dashboard.loading ? "loading" : "info"}
          title={initialLoadError || dashboard.error || dashboard.status || (isLoginActive ? "Login in progress" : "Ready")}
          detail={
            isLoginActive
              ? dashboard.loginFlow?.message || dashboard.loginFlow?.status || "Complete the browser login flow to finish adding the account."
              : dashboard.status || dashboard.preferences.refreshPolicy || "CX Switch is ready."
          }
          actionLabel={initialLoadError ? "Retry" : dashboard.error ? "Reload" : undefined}
          onAction={initialLoadError || dashboard.error ? () => void handleInitialLoad() : undefined}
        />
      ) : null}

      {isLoginActive ? (
        <div className="login-strip">
          <div className="login-strip-copy">
            <span className="login-strip-label">Login flow active</span>
            <strong>{dashboard.loginFlow?.message || dashboard.loginFlow?.status || "Finish the ChatGPT sign-in in your browser."}</strong>
          </div>
          <button
            className="inline-button"
            type="button"
            onClick={() =>
              void runAction("cancelAddAccount", dashboard.loginFlow?.loginId ? { loginId: dashboard.loginFlow.loginId } : {})
            }
            disabled={busyAction === "cancelAddAccount"}
          >
            Cancel
          </button>
        </div>
      ) : null}

      {showRefreshImport ? (
        <RefreshTokenImportPanel
          value={refreshTokenDraft}
          onChange={setRefreshTokenDraft}
          busy={busyAction === "importRefreshToken"}
          onImport={() => void runAction("importRefreshToken", { refreshToken: refreshTokenDraft })}
          onCancel={() => {
            if (busyAction === "importRefreshToken") {
              return;
            }
            setShowRefreshImport(false);
            setRefreshTokenDraft("");
          }}
          onPasteShortcut={() => void pasteRefreshTokenFromClipboard()}
          onPasteText={(text) => {
            setRefreshTokenDraft((current) => {
              const next = current ? `${current}\n${text}` : text;
              return next.trim();
            });
          }}
          inputRef={refreshImportRef}
        />
      ) : null}

      <section className="panel accounts-panel">
        <div className="panel-heading">
          <div>
            <p className="section-label">Switch Account</p>
            <h2>{sectionTitleCount(allAccountCount)}</h2>
          </div>
          <button
            className="inline-button inline-button-secondary"
            type="button"
            onClick={() => void runAction("refreshSavedAccounts")}
            disabled={busyAction === "refreshSavedAccounts" || dashboard.loading}
          >
            Refresh
          </button>
        </div>

        {savedAccounts.length > 0 ? (
          <div className="account-list">
            {savedAccounts.map((account) => (
                <AccountCard
                  key={account.id}
                  account={account}
                  showFullEmails={showEmail}
                  onSwitch={(selected) =>
                    void runAction(
                      "switchAccount",
                    selected.source.id || selected.source.chatgptAccountId || selected.source.email
                      ? {
                          id: selected.source.id ?? selected.id,
                          email: selected.source.email ?? selected.email,
                          chatgptAccountId: selected.source.chatgptAccountId ?? selected.chatgptAccountId,
                        }
                      : identityFromAccount(selected),
                  )
                }
                onRemove={(removed) =>
                  void runAction("removeAccount", {
                    id: removed.source.id ?? removed.id,
                    email: removed.source.email ?? removed.email,
                    chatgptAccountId: removed.source.chatgptAccountId ?? removed.chatgptAccountId,
                  })
                }
              />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>No saved accounts yet.</strong>
            <span>Use Add Account to create the first entry, or save the current live account.</span>
          </div>
        )}
      </section>

      <section className="panel footer-panel">
        <FooterAction
          title="Add Account"
          subtitle="Open the ChatGPT login flow"
          onClick={() => void runAction("startAddAccount")}
          active={busyAction === "startAddAccount" || isLoginActive}
          disabled={busyAction === "startAddAccount" || isLoginActive}
        />
        <FooterAction
          title={showRefreshImport ? "Close Import" : "Import Refresh Token"}
          subtitle="Paste a refresh token"
          onClick={() => setShowRefreshImport((current) => !current)}
          active={showRefreshImport}
          disabled={busyAction === "importRefreshToken"}
        />
        <FooterAction
          title="Status Page"
          subtitle="Open the OpenAI status page"
          onClick={() => void runAction("openStatusPage")}
          disabled={busyAction === "openStatusPage"}
        />
        <FooterAction
          title={showEmail ? "Hide Emails" : "Show Emails"}
          subtitle={showEmail ? "Mask addresses in the list" : "Reveal full email addresses"}
          onClick={() => {
            setShowFullEmails((current) => !current);
            void runAction("setMaskEmails", { maskEmails: !showEmail });
          }}
          disabled={busyAction === "setMaskEmails"}
          active={!showEmail}
        />
        <FooterAction
          title="Settings"
          subtitle={settingsSummary}
          onClick={() => void runAction("openSettings")}
          disabled={busyAction === "openSettings"}
        />
        <FooterAction
          title="Quit"
          subtitle="Exit CX Switch"
          onClick={() => void runAction("quitApp")}
          disabled={busyAction === "quitApp"}
          danger
        />
      </section>
    </div>
  );
}
