## Why

The review tracked by issue #105 identified remaining gaps in production
startup, socket lifecycle ownership, UI architecture, documentation, and
verification. These gaps affect data protection guarantees and make some
documented acceptance claims stronger than the repository evidence supports.

## What Changes

- Run resumable local-storage migration from the real production database
  bootstrap path.
- Explicitly own and cancel active socket stream subscriptions.
- Route native Settings operations through a UI-facing controller or facade.
- Reduce Settings rebuilds with field-specific provider selection.
- Correct schema, queue-column, and multi-peer documentation in both languages.
- Add explicit CI/OpenSpec verification and document device-only QA boundaries.

## Capabilities

### New Capabilities

- `production-storage-migration`
- `socket-subscription-lifecycle`
- `settings-architecture`
- `verification-documentation`

### Modified Capabilities

None.

## Impact

- Production bootstrap and database initialization.
- `SocketManager` teardown and replacement behavior.
- Settings controller, facade, and screen boundaries.
- Product documentation and CI workflows.
- Migration, socket, Settings, and verification tests.

