## 1. Dashboard State Flow

- [x] 1.1 Make the dashboard render cached account data before live refresh completes
- [x] 1.2 Preserve account identity fields and stored auth when live data merges back into the cache
- [x] 1.3 Keep refresh and switch operations isolated to the affected account record

## 2. SwiftUI View Structure

- [x] 2.1 Keep `MenuBarView` as a lightweight container that only composes the dashboard sections
- [x] 2.2 Keep account row and usage subviews focused on their own data instead of passing a broad context object
- [x] 2.3 Preserve stable identity for saved-account rows when the list updates

## 3. Layout and Messaging

- [x] 3.1 Make the menu bar panel height content-driven instead of fixed-height
- [x] 3.2 Keep usage rows compact with one label row below the progress indicator
- [x] 3.3 Separate loading, status, and error messaging so cache fallback does not collapse the full panel

## 4. Verification

- [x] 4.1 Verify cached-first rendering on open with live refresh finishing afterward
- [x] 4.2 Verify switching between accounts does not clear stored auth on unaffected rows
- [x] 4.3 Verify the panel remains compact with long emails, multiple accounts, and transient usage probe failures
