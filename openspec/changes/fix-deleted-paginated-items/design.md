## Context

Each grouped paginated provider fetches a recent authoritative window and
merges it into a cache that may also contain older loaded pages. Existing
merge logic can update duplicate identifiers but cannot distinguish a deleted
recent event from an older event that should remain cached.

The Home feed has the same issue independently: it listens to all three
facades, but its refresh prepends fresh items to the cached feed and
deduplicates by ID. Items absent from the fresh result therefore remain
visible after deletion.

## Decisions

### 1. Reconcile by recent event scope

The shared notifier will track the group keys represented by the previous
recent fetch. Before merging fresh groups, it will remove the previous recent
events from those groups and rebuild any remaining older events. Groups absent
from the fresh result are removed only when they belonged to the previous
recent scope. Older-only groups remain untouched.

Each feature provider supplies its group key, group events, and recent-window
predicate. Fresh groups are then merged with the retained older groups and
sorted normally.

### 2. Keep facade and DAO responsibilities unchanged

Facades continue to perform deletion and publish state. Providers remain the
only layer responsible for paginated UI state. No UI-to-DAO or UI-to-service
access is introduced.

### 3. Verify observable behavior

Tests will exercise facade deletion followed by provider refresh for Calls,
SMS, and Notifications. They will also verify partial deletion within a group,
last-item deletion, repeated refreshes, and older-page preservation.

Home feed tests will verify that deleting a call, SMS message, or notification
removes that item from the visible feed without requiring a restart.

## Risks

- Removing all records from a recent group must not remove older records in
  the same group; event-level recent filtering prevents this.
- A refresh must not erase older groups that were loaded by `loadMore()`;
  previous recent group keys limit reconciliation to the recent scope.
