## Why

Deleting Calls, SMS, or Notifications updates the database and facade state,
but the paginated list cache keeps records that are absent from the latest
recent query. Users only see the deletion after restarting the app.

## What Changes

- Reconcile recent paginated results authoritatively during refresh.
- Remove deleted events and empty groups from Calls, SMS, and Notifications.
- Remove deleted events from the paginated Home feed as well.
- Preserve older pages already loaded by pagination.
- Add regression coverage for single deletes, partial group deletes, empty
  groups, and preservation of older events.

## Capabilities

### New Capabilities

- `deleted-paginated-items`: Defines deletion reconciliation for grouped lists.

### Modified Capabilities

None.

## Impact

- Shared grouped pagination reconciliation.
- Call, SMS, and notification group providers.
- Provider regression tests.
- No database, protocol, or public facade API changes.
