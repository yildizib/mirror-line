## Context

See `proposal.md` for motivation and the capability specs for observable
behavior. Call and SMS facades already persist terminal status correctly and
publish updated state. Their paginated UI providers maintain separate loaded
caches, however, and currently keep the first same-identifier record during a
merge. Because existing cached records are merged before freshly fetched
records, stale `ringing` and `pending` values remain visible.

The SMS detail provider also starts with an empty, non-loading state and defers
its first load. The screen cannot distinguish that transient state from a
completed empty result, so it schedules an immediate route pop. Outgoing SMS
creation and transmission are also started without ordering, allowing a fast
status response to race the optimistic database insert.

The existing architecture boundary remains mandatory: base services are
accessed through facades, and UI state is derived through feature providers.
The UI will not query DAOs, sockets, or native channels directly.

## Goals / Non-Goals

**Goals:**

- Make freshly persisted same-identifier records authoritative during call and
  SMS pagination refreshes while preserving already loaded older pages.
- Prevent an outgoing SMS acknowledgement from racing its optimistic record.
- Represent completion of the SMS detail provider's initial load explicitly.
- Cover provider-level state replacement and user-visible navigation behavior
  with regression tests.

**Non-Goals:**

- Redesign the socket protocol or add application-level delivery receipts.
- Change Android SMS dispatch semantics from accepted-by-platform to carrier
  delivery confirmation.
- Generalize every paginated feature or reconcile unrelated deletion and
  overlapping-refresh behavior in this bugfix.
- Change database schemas, public APIs, or feature architecture boundaries.

## Decisions

### 1. Fresh records replace cached records with the same identifier

Call and SMS grouped pagination merges will treat the newly fetched window as
authoritative for every identifier present in that window. Existing loaded
events with those identifiers will be removed before fresh groups are merged,
then groups will be rebuilt and sorted. This handles both field changes, such
as `ringing` to `missed`, and movement between grouping keys without retaining
a stale duplicate. Existing events absent from the fresh window remain loaded
so older pagination progress is preserved.

SMS detail refresh will likewise merge fresh messages before cached messages
when deduplicating by identifier, then restore chronological ordering.

Alternatives considered:

- Reading facade state directly in widgets was rejected because it would split
  pagination responsibility across the UI and provider layers.
- Replacing the entire paginated state with the fresh window was rejected
  because it would discard older pages the user already loaded.
- Changing the shared deduplication helper globally was rejected because some
  callers intentionally control precedence through input order.

### 2. Persist the optimistic SMS before transmission

The reply action will become asynchronous and await insertion of the local
`pending` message before requesting transmission. This establishes the record
that an immediate `sent` or `failed` response must update. The composer may be
cleared after the local insert and send request have been initiated in the
defined order.

Alternatives considered:

- Buffering unknown SMS statuses inside the facade would handle more transport
  reorder cases but adds lifecycle state that is unnecessary when this local
  send path can guarantee insertion order.
- Removing optimistic rendering was rejected because immediate feedback is a
  desired part of the existing SMS experience.

### 3. Track initial SMS detail load completion explicitly

Paginated state will expose whether its initial load has completed. The SMS
detail screen will treat empty items as a removable thread only after that flag
is true and loading is false. Any post-frame pop will re-read the provider and
verify those conditions before navigating, preventing a callback scheduled
from stale build state from closing a now-populated route.

Alternatives considered:

- Starting the load without a microtask reduces the timing window but does not
  model the semantic difference between uninitialized and confirmed empty.
- Removing automatic pop entirely was rejected because a thread whose messages
  were deleted should still return to the thread list.
- Making the family provider auto-dispose was rejected because disposal does
  not fix the first-build ambiguity.

### 4. Test state transitions at provider and widget boundaries

Provider tests will update an existing call or SMS identifier and assert that
the paginated state contains one record with the latest status. SMS detail
tests will cover both `pending` to `sent` replacement and initial-load
completion. A widget test will tap a populated SMS thread once and assert that
the detail route remains open through loading.

The tests will use facade/provider seams and will not bypass architecture by
calling base services from UI tests.

## Risks / Trade-offs

- [Fresh-window reconciliation could remove a cached event from its old group
  before adding its new group] -> Rebuild and sort groups as one operation, and
  test grouping-key movement with one final occurrence of the identifier.
- [A generic initial-load flag affects the shared pagination state type] -> Add
  a backward-compatible default and update only code that needs the semantic
  distinction in this change.
- [Awaiting the optimistic insert slightly delays transmission] -> The local
  database write is required for correctness and remains short; retain the
  optimistic bubble as immediate feedback once insertion completes.
- [A socket-level acknowledgement can still be lost after a successful write]
  -> Keep the existing stale-pending timeout; transport acknowledgement changes
  remain outside this focused UI-state fix.

## Migration Plan

No data or schema migration is required. Deploy the provider, send-ordering,
and navigation-state changes together with their regression tests. Rollback is
the normal code revert because persisted call and SMS records remain compatible
with both versions.
