## ADDED Requirements

### Requirement: Cached-first dashboard rendering
The dashboard MUST render the last known account cache immediately when the menu opens, before any live refresh completes. Live data MAY reconcile afterward, but cached account rows and current-account content MUST remain visible during the refresh.

#### Scenario: Menu opens with cached data available
- **WHEN** the user opens the menu bar dashboard and a cached current account exists
- **THEN** the dashboard shows the cached current account and saved accounts immediately
- **AND** the dashboard does not wait for live app-server data before rendering

#### Scenario: Live refresh completes after cached render
- **WHEN** the dashboard has already rendered cached account data
- **THEN** the live refresh MAY update the affected account records
- **AND** the dashboard MUST remain visible during the update

### Requirement: Per-account refresh isolation
Refresh and switching actions MUST update only the affected account record and MUST NOT reset unrelated account rows or clear their cached state. If a refresh falls back to cached usage data, the cached record MUST remain associated with the same account identity.

#### Scenario: Refresh one saved account
- **WHEN** the user refreshes a single saved account
- **THEN** only that account's cached usage data is updated or reused
- **AND** the other saved accounts retain their existing cached state

#### Scenario: Switch back to a previously used account
- **WHEN** the user switches away from an account and later switches back
- **THEN** the account MUST keep its stored authentication and metadata if it exists locally
- **AND** switching back MUST not depend on a full dashboard reset

### Requirement: Content-driven menu sizing
The menu bar dashboard MUST size itself to its content instead of relying on a fixed panel height. Account sections, usage rows, and footer actions MUST remain compact enough to avoid unnecessary vertical whitespace in the common case.

#### Scenario: Fewer visible rows
- **WHEN** the dashboard contains only the current account and a small number of saved accounts
- **THEN** the panel height shrinks to fit the rendered content
- **AND** the panel does not keep a large empty area below the last visible section

#### Scenario: Account rows with usage details
- **WHEN** an account row displays usage information
- **THEN** the row shows the usage label, progress indicator, and reset timing without duplicating the label on multiple lines
- **AND** the layout remains readable in a narrow menu bar panel

### Requirement: Stable view identity and state separation
The dashboard MUST preserve stable identity for account rows and MUST keep loading, status, and error messaging separate. A transient refresh failure MUST NOT clear unrelated cached account data or collapse the dashboard into a single error state.

#### Scenario: Refresh fails for one account
- **WHEN** a usage refresh fails for a single account
- **THEN** the dashboard continues to show the other cached account rows
- **AND** the failure is surfaced as a scoped error or fallback state for that account only

#### Scenario: Re-render after account list changes
- **WHEN** the saved account list changes order or content
- **THEN** each row remains keyed to a stable account id
- **AND** the dashboard does not treat row position as identity

