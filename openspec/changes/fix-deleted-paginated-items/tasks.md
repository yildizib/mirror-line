## 1. Shared reconciliation

- [x] 1.1 Track the previous recent group scope in the shared grouped
  pagination notifier.
- [x] 1.2 Rebuild cached groups by removing stale recent events while
  preserving older events and older-only groups.

## 2. Feature providers

- [x] 2.1 Add group event/key and recent-window hooks to Calls, SMS, and
  Notifications providers.
- [x] 2.2 Keep existing update, grouping, sorting, and pagination behavior.
- [ ] 2.3 Reconcile the Home feed refresh so source items absent from the
  authoritative recent result are removed from the visible feed.

## 3. Regression tests

- [x] 3.1 Cover deletion and empty-group reconciliation for Calls.
- [x] 3.2 Cover deletion and empty-group reconciliation for SMS.
- [x] 3.3 Cover deletion and empty-group reconciliation for Notifications.
- [x] 3.4 Cover partial deletion, older-page preservation, and repeated
  refreshes.
- [ ] 3.5 Add Home feed regression coverage for deletion of Calls, SMS, and
  Notifications items.

## 4. Verification

- [x] 4.1 Run formatting, analyzers, focused tests, complete tests, OpenSpec
  validation, and debug APK build.
