## Why

The menu bar dashboard already works, but the current requirements do not fully capture the SwiftUI quality bar we want for this app. We need a spec that keeps cached data visible during refreshes, avoids layout thrash, and defines stable per-account state so the UI stays predictable under frequent switching.

## What Changes

- Add a new dashboard-quality capability that defines stable cached-first rendering, per-account refresh isolation, and content-driven sizing.
- Require the menu bar panel to preserve previously loaded account data while live data refreshes in the background.
- Require refresh and switching actions to update only the affected account record instead of reloading the entire panel state.
- Require the dashboard layout to remain compact and content-sized, with no fixed-height assumptions that create empty space or clipping.
- Require clearer separation between loading, status, and error messaging so transient refresh failures do not disrupt the whole panel.
- Require interactive controls to remain button-driven and accessible, with stable identity for repeated account rows.

## Capabilities

### New Capabilities
- `menu-bar-dashboard-stability`: Stable cached-first menu bar dashboard behavior, including per-account refresh isolation, content-driven layout, and non-blocking status handling.

### Modified Capabilities
- None

## Impact

- Affects the menu bar SwiftUI views, account refresh orchestration, and dashboard state flow.
- May simplify or refactor `AppState`, `MenuBarView`, `CurrentAccountSection`, `SavedAccountRow`, and `UsageBar` to better match the spec.
- No backend API changes are required.

