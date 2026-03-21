import type { RPCSchema } from "electrobun/bun";

export const APP_NAME = "CX Switch";

export type PlanType =
  | "free"
  | "go"
  | "plus"
  | "pro"
  | "team"
  | "business"
  | "enterprise"
  | "edu"
  | "unknown";

export type UsageWindow = {
  label: string;
  windowDurationMins: number;
  usedPercent: number;
  resetsAt: number | string | null;
  remainingSeconds?: number | null;
  resetText?: string | null;
};

export type UsageSnapshot = {
  limitId: string | null;
  planType: PlanType | null;
  updatedAt: string | null;
  windows: UsageWindow[];
  primary: UsageWindow | null;
  secondary: UsageWindow | null;
  credits?: {
    hasCredits: boolean;
    unlimited: boolean;
    balance: string | null;
  } | null;
};

export type AccountAuthBlob = {
  OPENAI_API_KEY?: string | null;
  auth_mode?: string | null;
  last_refresh?: string | null;
  tokens?: {
    access_token?: string | null;
    account_id?: string | null;
    id_token?: string | null;
    refresh_token?: string | null;
  } | null;
};

export type AccountRegistryEntry = {
  id: string;
  email: string;
  maskedEmail: string;
  planType: PlanType | null;
  chatgptAccountId: string | null;
  addedAt: string;
  lastUsedAt: string | null;
  usageSnapshot: UsageSnapshot | null;
  authKeychainKey?: string;
  usageError?: string | null;
  active?: boolean;
  isCurrent?: boolean;
  current?: boolean;
};

export type AppPreferences = {
  maskEmails: boolean;
  refreshPolicy: string;
  dataFolder: string;
};

export type LoginFlowState = {
  active: boolean;
  loginId: string | null;
  authUrl: string | null;
  status: string | null;
  message: string | null;
  error: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
};

export type DashboardState = {
  appName: string;
  loading: boolean;
  refreshing: boolean;
  updatedAt: string | null;
  currentAccount: AccountRegistryEntry | null;
  savedAccounts: AccountRegistryEntry[];
  preferences: AppPreferences;
  loginFlow: LoginFlowState;
  status: string | null;
  error: string | null;
  notice: string | null;
};

export type DashboardStateMessage = DashboardState;

export type AccountIdentity = {
  id?: string;
  email?: string;
  chatgptAccountId?: string | null;
};

export type AppRPC = {
  bun: RPCSchema<{
    requests: {
      getDashboardState: {
        params: {};
        response: DashboardState;
      };
      refreshCurrentAccount: {
        params: {};
        response: DashboardState;
      };
      refreshSavedAccounts: {
        params: {};
        response: DashboardState;
      };
      saveCurrentAccount: {
        params: AccountIdentity;
        response: DashboardState;
      };
      importRefreshToken: {
        params: { refreshToken: string };
        response: DashboardState;
      };
      readClipboardText: {
        params: {};
        response: string;
      };
      startAddAccount: {
        params: {};
        response: DashboardState;
      };
      cancelAddAccount: {
        params: { loginId?: string | null };
        response: DashboardState;
      };
      switchAccount: {
        params: AccountIdentity;
        response: DashboardState;
      };
      removeAccount: {
        params: AccountIdentity;
        response: DashboardState;
      };
      setMaskEmails: {
        params: { maskEmails: boolean };
        response: DashboardState;
      };
      openStatusPage: {
        params: {};
        response: boolean;
      };
      openSettings: {
        params: {};
        response: boolean;
      };
      quitApp: {
        params: {};
        response: boolean;
      };
    };
    messages: {
      dashboardStateUpdated: {
        state: DashboardStateMessage;
      };
    };
  }>;
  webview: RPCSchema<{
    requests: {};
    messages: {
      dashboardStateUpdated: {
        state: DashboardStateMessage;
      };
    };
  }>;
};
