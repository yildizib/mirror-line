## Why

Device testing found that the Calls and SMS screens can display stale state or
immediately undo navigation even though the underlying operation succeeds. The
UI must consistently reflect persisted communication state and respond to the
first user interaction.

## What Changes

- Make terminal incoming-call state replace the previously displayed ringing
  state so missed calls no longer retain a Reject action.
- Make outgoing SMS status updates replace the optimistic pending state in both
  conversation and thread-list views.
- Ensure the optimistic outgoing SMS record exists before transmission can
  return a status update.
- Keep an SMS thread route open while its initial messages are loading, and
  open a populated thread with a single tap.
- Add regression coverage for call status refresh, SMS status refresh, and
  first-tap thread navigation.

## Capabilities

### New Capabilities

- `call-ui-state`: Defines how call screens reflect terminal call status and
  expose actions only for active ringing calls.
- `sms-ui-state`: Defines outgoing SMS status synchronization and single-tap
  conversation navigation behavior.

### Modified Capabilities

None.

## Impact

- Call grouping and paginated refresh state under `lib/features/calls/`.
- SMS send, grouping, detail pagination, and navigation state under
  `lib/features/sms/`.
- Shared pagination behavior where fresh records must replace loaded records
  with the same identity.
- Call and SMS notifier, provider, and widget regression tests.
- No protocol, public API, dependency, or database schema changes.
