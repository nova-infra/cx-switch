## Registry -> SQLite Mapping

### `accounts` table

`registry.json` account fields map to `accounts` like this:

| Registry field | DB column | Notes |
|---|---|---|
| `id` | `accounts.id` | Primary key. Keep the existing value during migration. |
| `email` | `accounts.email` | Authoritative display identity from registry. |
| `maskedEmail` | `accounts.masked_email` | Import as-is for compatibility; UI can recompute later. |
| `accountType` | `accounts.account_type` | Store raw enum string such as `oauth`. |
| `planType` | `accounts.plan_type` | Store raw enum string such as `team`. |
| `chatgptAccountId` | `accounts.chatgpt_account_id` | May differ from `id` for legacy records. |
| `addedAt` | `accounts.added_at` | ISO8601 text. |
| `lastUsedAt` | `accounts.last_used_at` | ISO8601 text or `NULL`. |
| `isCurrent` | `accounts.is_current` | Normalize to a single current row before commit. |
| `usageError` | `accounts.usage_error` | Keep as-is. |

### `credentials` table

| Source | DB column | Notes |
|---|---|---|
| `storedAuth` | `credentials.auth_blob` | Decode base64 -> JSON string -> store raw JSON text. |
| `authKeychainKey` | `credentials.auth_blob` | Only fallback if `storedAuth` is missing. Read via `KeychainService`. |
| `id` | `credentials.account_id` | Foreign key to `accounts.id`. |
| `storedAuth` decode success time | `credentials.updated_at` | Prefer `AuthBlob.lastRefresh`; otherwise use migration time. |

Important:
- `storedAuth` is the preferred migration source.
- `authKeychainKey` is legacy-only and should be read once during migration, then dropped.
- A record with no credential should still migrate into `accounts`; it just cannot become switchable until repaired.

### `usage_snapshots` table

| Source | DB column | Notes |
|---|---|---|
| `usageSnapshot` | `usage_snapshots.snapshot_json` | Store JSON-encoded snapshot payload. |
| `id` | `usage_snapshots.account_id` | Foreign key to `accounts.id`. |
| `usageSnapshot.updatedAt` | `usage_snapshots.updated_at` | Fallback to `lastUsedAt`, then migration time. |

## Safe Migration Order

### Can be implemented first

1. Create `cx-switch.db` and all three tables.
2. Add migration audit tooling for `registry.json`.
3. Implement account import from registry into `accounts`.
4. Implement credential import from `storedAuth`.
5. Add keychain fallback import for accounts that still have `authKeychainKey`.

### Must wait for DB service to exist

1. Replacing `AppState.loadDashboard()` reads from `accountDB`.
2. Replacing `switchAccount()` to load credentials from DB.
3. Replacing `importRefreshToken()` to persist credentials into DB.
4. Removing `storedAuth`, `authKeychainKey`, and registry debounce logic.

### Should happen only after DB-backed reads are stable

1. Rename `registry.json` -> `registry.json.migrated`.
2. Remove `AccountStore.loadRegistry()` / `saveRegistry()`.
3. Remove `encodeStoredAuth` / `decodeStoredAuth` / `resolveAuthBlob`.
4. Remove `accountCacheByID` and registry write debounce.

## Recommended Migration Transaction

1. Open DB.
2. Enable `WAL` and `foreign_keys`.
3. Begin transaction.
4. Import `accounts`.
5. Import `credentials`.
6. Import `usage_snapshots`.
7. Normalize the single current account.
8. Commit transaction.
9. Rename `registry.json` to `.migrated` only after commit succeeds.

## Current Account Normalization

Migration should guarantee at most one current account:

1. Prefer the account matching `auth.json` identity, if `auth.json` exists and can be decoded.
2. Otherwise prefer the sole `isCurrent == true` account.
3. If multiple rows are marked current, prefer the one with a valid credential.
4. If still tied, prefer the most recent `lastUsedAt`.

## Validation Priorities

1. Run an audit before migration and confirm:
   - duplicate IDs
   - duplicate emails
   - missing credentials
   - multiple current accounts
2. Run migration once and verify:
   - account count matches expectation
   - credential count is not less than the number of valid `storedAuth` entries
   - usage snapshot count matches migrated snapshots
3. Delete `auth.json` and verify DB can restore the current credential.

## Known Failure Modes To Guard Against

1. Corrupted `storedAuth` base64 or invalid JSON causing silent credential loss.
2. Multiple rows marked current leading to a different active account after migration.
3. Renaming `registry.json` before credential import succeeds, leaving no recoverable source of truth.
