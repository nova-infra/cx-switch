import type { PlanType, UsageSnapshot, UsageWindow } from "../shared/rpc";
import type { AccountAuthBlob } from "./accountStore";

const CHATGPT_CODEX_URL = "https://chatgpt.com/backend-api/codex/responses";
const DEFAULT_MODEL = "gpt-5.1-codex";
const DEFAULT_INSTRUCTIONS = "You are Codex, a terminal-based coding assistant.";
const FIVE_HOUR_WINDOW_MINS = 300;
const WEEKLY_WINDOW_MINS = 10_080;

type RawRateLimitWindow = {
  usedPercent: number;
  resetsAt?: number | null;
  windowDurationMins?: number | null;
};

type RawRateLimitSnapshot = {
  limitId?: string | null;
  planType?: PlanType | null;
  primary?: RawRateLimitWindow | null;
  secondary?: RawRateLimitWindow | null;
  credits?: {
    hasCredits: boolean;
    unlimited: boolean;
    balance: string | null;
  } | null;
};

export function selectRateLimitSnapshot(result: {
  rateLimits: RawRateLimitSnapshot | null;
  rateLimitsByLimitId?:
    | Record<string, RawRateLimitSnapshot | null | undefined>
    | null;
}): RawRateLimitSnapshot | null {
  if (result.rateLimitsByLimitId?.codex) {
    return result.rateLimitsByLimitId.codex;
  }

  const firstBucket = Object.values(result.rateLimitsByLimitId ?? {}).find(
    Boolean,
  );
  return firstBucket ?? result.rateLimits ?? null;
}

export function normalizeUsageSnapshot(
  snapshot: RawRateLimitSnapshot | null | undefined,
  source: "live" | "probe",
  fallbackPlanType: PlanType | null = null,
): UsageSnapshot | null {
  if (!snapshot) {
    return null;
  }

  const windows = [snapshot.primary ?? null, snapshot.secondary ?? null].filter(
    (entry): entry is RawRateLimitWindow => Boolean(entry),
  );
  if (windows.length === 0) {
    return null;
  }

  const normalized = resolveUsageWindows(windows);
  const primary = toUsageWindow(normalized.fiveHours, "5 Hours");
  const secondary = toUsageWindow(normalized.weekly, "Weekly");

  return {
    limitId: snapshot.limitId ?? "codex",
    planType: snapshot.planType ?? fallbackPlanType,
    updatedAt: new Date().toISOString(),
    windows: [primary, secondary].filter(
      (entry): entry is UsageWindow => Boolean(entry),
    ),
    primary,
    secondary:
      secondary && primary && secondary.windowDurationMins === primary.windowDurationMins
        ? null
        : secondary,
    credits: snapshot.credits ?? null,
  };
}

function resolveUsageWindows(windows: RawRateLimitWindow[]): {
  fiveHours: RawRateLimitWindow | null;
  weekly: RawRateLimitWindow | null;
} {
  const fiveHourExact = pickWindow(windows, FIVE_HOUR_WINDOW_MINS);
  const weeklyExact = pickWindow(windows, WEEKLY_WINDOW_MINS);

  if (fiveHourExact || weeklyExact) {
    return {
      fiveHours: fiveHourExact ?? inferFiveHourWindow(windows, weeklyExact),
      weekly: weeklyExact ?? inferWeeklyWindow(windows, fiveHourExact),
    };
  }

  const orderedByReset = [...windows].sort(compareWindowResetAscending);
  if (orderedByReset.length >= 2) {
    return {
      fiveHours: orderedByReset[0] ?? null,
      weekly: orderedByReset[orderedByReset.length - 1] ?? null,
    };
  }

  const orderedByDuration = [...windows].sort(compareWindowDurationAscending);
  return {
    fiveHours: orderedByDuration[0] ?? null,
    weekly: orderedByDuration.at(-1) ?? null,
  };
}

function inferFiveHourWindow(
  windows: RawRateLimitWindow[],
  exclude: RawRateLimitWindow | null | undefined,
): RawRateLimitWindow | null {
  const candidates = windows.filter((window) => window !== exclude);
  const byReset = [...candidates].sort(compareWindowResetAscending);
  return byReset[0] ?? candidates[0] ?? null;
}

function inferWeeklyWindow(
  windows: RawRateLimitWindow[],
  exclude: RawRateLimitWindow | null | undefined,
): RawRateLimitWindow | null {
  const candidates = windows.filter((window) => window !== exclude);
  const byReset = [...candidates].sort(compareWindowResetAscending);
  return byReset.at(-1) ?? candidates.at(-1) ?? null;
}

export async function probeUsageSnapshot(params: {
  auth: AccountAuthBlob;
  planType: PlanType | null;
  cliVersion: string;
  timeoutMs: number;
}): Promise<UsageSnapshot | null> {
  const accessToken = params.auth.tokens?.access_token;
  if (!accessToken) {
    throw new Error("Missing access token for saved account.");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), params.timeoutMs);

  try {
    const response = await fetch(CHATGPT_CODEX_URL, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "text/event-stream",
        "Content-Type": "application/json",
        "OpenAI-Beta": "responses=experimental",
        Originator: "codex_cli_rs",
        Version: params.cliVersion,
        "User-Agent": `codex_cli_rs/${params.cliVersion}`,
        ...(params.auth.tokens?.account_id
          ? { "chatgpt-account-id": params.auth.tokens.account_id }
          : {}),
      },
      body: JSON.stringify({
        model: DEFAULT_MODEL,
        input: [
          {
            role: "user",
            content: [{ type: "input_text", text: "hi" }],
          },
        ],
        instructions: DEFAULT_INSTRUCTIONS,
        max_output_tokens: 1,
        store: false,
        stream: true,
      }),
    });

    const parsedSnapshot = parseProbeHeaders(response.headers, params.planType);
    void response.body?.cancel();

    if (!response.ok && !parsedSnapshot) {
      if (response.status === 401) {
        throw new Error("Saved account token expired. Sign in again.");
      }

      throw new Error(`Probe request failed with status ${response.status}.`);
    }

    return normalizeUsageSnapshot(parsedSnapshot, "probe", params.planType);
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("Usage probe timed out.");
    }

    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function parseProbeHeaders(
  headers: Headers,
  planType: PlanType | null,
): RawRateLimitSnapshot | null {
  const primary = parseWindowFromHeaders(headers, "primary");
  const secondary = parseWindowFromHeaders(headers, "secondary");

  if (!primary && !secondary) {
    return null;
  }

  return {
    limitId: "codex",
    planType,
    primary,
    secondary,
  };
}

function parseWindowFromHeaders(
  headers: Headers,
  key: "primary" | "secondary",
): RawRateLimitWindow | null {
  const usedPercent = parseFloatHeader(
    headers,
    `x-codex-${key}-used-percent`,
  );
  if (usedPercent === null) {
    return null;
  }

  const resetAfterSeconds = parseIntHeader(
    headers,
    `x-codex-${key}-reset-after-seconds`,
  );
  const windowDurationMins = parseIntHeader(
    headers,
    `x-codex-${key}-window-minutes`,
  );

  return {
    usedPercent,
    resetsAt:
      resetAfterSeconds === null
        ? null
        : Math.floor(Date.now() / 1000) + resetAfterSeconds,
    windowDurationMins,
  };
}

function parseFloatHeader(headers: Headers, key: string): number | null {
  const raw = headers.get(key);
  if (!raw) {
    return null;
  }

  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseIntHeader(headers: Headers, key: string): number | null {
  const raw = headers.get(key);
  if (!raw) {
    return null;
  }

  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function compareWindowDurationAscending(
  left: RawRateLimitWindow,
  right: RawRateLimitWindow,
): number {
  return (left.windowDurationMins ?? Number.MAX_SAFE_INTEGER) -
    (right.windowDurationMins ?? Number.MAX_SAFE_INTEGER);
}

function compareWindowResetAscending(
  left: RawRateLimitWindow,
  right: RawRateLimitWindow,
): number {
  return (left.resetsAt ?? Number.MAX_SAFE_INTEGER) -
    (right.resetsAt ?? Number.MAX_SAFE_INTEGER);
}

function pickWindow(
  windows: RawRateLimitWindow[],
  durationMins: number,
): RawRateLimitWindow | null {
  const exact = windows.find(
    (window) => window.windowDurationMins === durationMins,
  );
  if (exact) {
    return exact;
  }

  const sorted = [...windows].sort((left, right) => {
    const leftDistance = Math.abs(
      (left.windowDurationMins ?? durationMins) - durationMins,
    );
    const rightDistance = Math.abs(
      (right.windowDurationMins ?? durationMins) - durationMins,
    );
    return leftDistance - rightDistance;
  });

  return sorted[0] ?? null;
}

function toUsageWindow(
  window: RawRateLimitWindow | null,
  label: string,
): UsageWindow | null {
  if (!window) {
    return null;
  }

  const resetsAtMs =
    typeof window.resetsAt === "number" && Number.isFinite(window.resetsAt)
      ? window.resetsAt * 1000
      : null;
  const remainingSeconds =
    resetsAtMs === null
      ? null
      : Math.max(0, Math.floor((resetsAtMs - Date.now()) / 1000));

  return {
    label,
    windowDurationMins: window.windowDurationMins ?? 0,
    usedPercent: Math.max(0, Math.round(window.usedPercent)),
    resetsAt: resetsAtMs === null ? null : new Date(resetsAtMs).toISOString(),
    remainingSeconds,
    resetText:
      remainingSeconds === null
        ? null
        : remainingSeconds <= 0
          ? "Resets soon"
          : null,
  };
}
