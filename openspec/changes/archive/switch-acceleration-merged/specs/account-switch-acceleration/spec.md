## ADDED Requirements

### Requirement: Optimistic account switching
The system SHALL update the active account in the UI immediately after the selected account auth is written, without waiting for `account/read` to complete.

#### Scenario: Switch to a saved account
- **WHEN** the user selects a saved account with a resolved auth blob
- **THEN** the system SHALL mark that account as active immediately
- **AND** the system SHALL continue background reconciliation after the UI update

### Requirement: Background reconciliation
The system MUST continue probing `account/read` after an optimistic switch and merge live account data when available.

#### Scenario: Live data arrives later
- **WHEN** `account/read` returns a live account after the switch
- **THEN** the system SHALL merge the live account metadata and usage snapshot into the cached account record
- **AND** the system SHALL preserve stored auth and existing registry-only fields

### Requirement: Non-blocking import completion
The system SHALL show an imported account immediately after auth file replacement and continue metadata reconciliation in the background.

#### Scenario: Refresh token import succeeds
- **WHEN** a refresh token import writes a valid auth file
- **THEN** the system SHALL surface the imported account as current without waiting for readiness polling to finish
- **AND** the system SHALL continue background reconciliation to fill missing fields

### Requirement: Coalesced registry persistence
The system MUST coalesce repeated registry writes caused by rapid refresh and reconciliation updates.

#### Scenario: Multiple updates happen quickly
- **WHEN** several account updates occur within the debounce window
- **THEN** the system SHALL write the registry at most once for that window
- **AND** the persisted snapshot SHALL contain the latest merged account data

### Requirement: Account-scoped refresh state
The system SHALL track refresh state per account so one account refresh does not block unrelated accounts.

#### Scenario: Refresh one account row
- **WHEN** the user refreshes a single saved account row
- **THEN** only that account row SHALL display loading state
- **AND** other account rows SHALL remain interactive

### Requirement: Non-blocking fallback on reconciliation failure
The system SHALL retain the optimistic account state if background reconciliation fails and present a non-blocking status message.

#### Scenario: Readiness check times out
- **WHEN** the system cannot complete `account/read` within the readiness window
- **THEN** the selected account SHALL remain active in the UI
- **AND** the system SHALL show a status message rather than blocking the panel
