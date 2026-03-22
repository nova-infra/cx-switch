## Context

CX Switch already exposes a functional menu bar dashboard, but the current implementation has accumulated several cross-cutting concerns: cached account data, live refreshes, per-account status, and compact menu layout all interact through the same `AppState`. The SwiftUI skill for this project pushes us to keep view bodies simple, avoid unnecessary state fan-out, preserve stable identity in lists, and keep the UI responsive under frequent updates.

The goal of this design is not to add new backend behavior. It is to make the dashboard state flow and layout contract explicit enough that the SwiftUI implementation stays stable when accounts are refreshed, switched, or repaired.

## Goals / Non-Goals

**Goals:**
- Preserve cached account data as the first thing the user sees.
- Keep refresh operations isolated to the affected account.
- Make the menu bar panel content-sized instead of relying on fixed height.
- Separate loading, status, and error messaging so transient failures do not collapse the UI.
- Keep list identity stable and views composable so repeated refreshes do not cause unnecessary redraws.

**Non-Goals:**
- No new backend API surface.
- No redesign of the authentication protocol or account data model contract.
- No change to how account switching is initiated from the app server.
- No Liquid Glass or visual re-theme work beyond the existing menu bar style.

## Decisions

1. **Keep `AppState` as the orchestration layer, but make the account cache the source of truth for UI persistence.**
   - `AppState` will continue to own account loading, refresh orchestration, and status updates.
   - The account cache should preserve `storedAuth`, `planType`, `accountType`, `chatgptAccountId`, and `usageSnapshot` across live refreshes.
   - Alternative considered: split into separate store objects for cache, refresh, and login. Rejected for now because it would add more moving parts without improving the current feature scope.

2. **Refresh per account, not per panel.**
   - Each account gets its own refresh task and refresh lifecycle.
   - A refresh only updates the targeted account record and the current account if they are the same logical identity.
   - Alternative considered: a single panel-wide refresh button that reloads everything. Rejected because it creates unnecessary redraws, obscures which account is active, and conflicts with the existing per-account UX.

3. **Treat dashboard rendering as cached-first, live-second.**
   - The menu bar should render cached account data immediately, then reconcile with live account data after app-server initialization.
   - Live data can overwrite usage or metadata only when it is newer and still matches the same account identity.
   - Alternative considered: always block until live data is ready. Rejected because it makes the menu feel slow and fragile under reconnects.

4. **Keep views pure and narrowly scoped.**
   - `MenuBarView` should coordinate sections only.
   - `CurrentAccountSection`, `SavedAccountRow`, `UsageBar`, and `FooterActions` should remain presentation-focused and receive only the values they render.
   - Alternative considered: passing a large context object into every view. Rejected because it widens update fan-out and makes the body harder to reason about.

5. **Make layout content-driven rather than height-driven.**
   - The menu should size to content with minimal empty space.
   - Usage rows should remain compact and avoid duplicate label lines.
   - Horizontal arrangements should be preferred over extra vertical stacking when information can fit cleanly on one line.
   - Alternative considered: fixed height plus internal scrolling. Rejected because it creates dead space in the common case and makes the menu feel less native.

6. **Separate status, loading, and error semantics.**
   - Transient refresh progress should not masquerade as an error.
   - Status messages should be short-lived and non-blocking.
   - Error messages should only reflect actionable failures or real data-loss states.
   - Alternative considered: a single message banner for all states. Rejected because it makes the panel ambiguous and noisy.

7. **Use stable identity for account lists and refresh scheduling.**
   - Account rows should stay keyed by the account id, not array position.
   - Scheduling and rendering must not rely on list order for identity.
   - Alternative considered: rebuilding the account array in-place on every refresh. Rejected because it increases diff churn and creates opportunities for state loss.

## Risks / Trade-offs

- [More state bookkeeping] → Mitigate by keeping refresh and merge rules centralized in `AppState` and avoiding ad-hoc mutations in views.
- [Auto-refresh races with manual refresh] → Mitigate by tracking per-account refresh state and cancelling or coalescing duplicate work.
- [Content-driven layout may grow taller than expected for large data] → Mitigate by keeping rows compact and ensuring long text truncates gracefully.
- [Preserving cached data can hide live regressions temporarily] → Mitigate by surfacing brief, user-friendly status messages when refresh falls back to cache.

## Migration Plan

1. Update the dashboard state merging rules so account identity and saved auth are preserved across live refreshes.
2. Keep the current UI structure, but tighten the view boundaries so each subview renders only its own slice of data.
3. Validate the menu height and row spacing with real account data, including long emails and repeated refreshes.
4. Verify that manual refresh, auto-refresh, and account switching all update only the affected account.
5. Roll back by restoring the previous state-merging behavior if any account identity or refresh regression appears.

## Open Questions

- Should the auto-refresh scheduling remain active only while the app is running, or should it also rehydrate immediately after relaunch?
- Do we want an explicit “using cached usage” hint when refresh falls back to stored data?
- Should the dashboard show a separate visual treatment for live-reconciled vs. cached-only account data?

