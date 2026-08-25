## Context

See `proposal.md` for the observed failure. The current connection facade owns
one socket reference that can represent either a pairing/peer listener or an
outbound client, while reconnect triggers can arrive from timers, network
events, manual actions, and discovery callbacks. The existing endpoint guards
protect many normal paths but do not consistently gate forced reconnects while
the peer row is still self-only.

## Goals / Non-Goals

**Goals:**

- Make completed remote identity the single prerequisite for normal reconnect
  and fallback discovery.
- Keep pairing listener ownership separate from outbound client ownership.
- Make scheduler failure handling and backoff deterministic and bounded.
- Preserve the existing pairing protocol and role behavior.

**Non-Goals:**

- Redesign the QR payload or pairing handshake protocol.
- Change peer persistence schema.
- Add a new networking dependency.
- Change source-role telephony or beacon semantics beyond protecting their
  listener lifecycle.

## Decisions

### Gate all normal reconnect entry points

Use one facade-level completed-remote-peer predicate at every entry point that
can initiate normal reconnect or subnet discovery: network-change handling,
manual force reconnect, parallel force-connect, and scheduled reconnect
callbacks. This is preferred over relying only on the scheduler because the
scheduler does not own pairing state.

Alternative considered: add pairing-state knowledge to `ReconnectScheduler`.
Rejected because it would couple a generic timer to facade and persistence
state and would still leave manual/discovery paths ungated.

### Separate listener and client socket ownership

Before an outbound connection is attempted, the facade SHALL ensure the socket
being used is client-capable. If a pairing listener is still active, normal
reconnect is blocked until the listener is no longer needed or a separate
client socket is created. The pairing listener must not be converted in place.

Alternative considered: call `stopServer()` and reuse the same object.
Rejected because it creates lifecycle races with incoming pairing requests and
can close the transaction socket unexpectedly.

### Make reconnect results explicit

Represent the reconnect callback result as success/failure rather than a
`Future<void>` whose completion can be mistaken for success. The scheduler
increments retry state and schedules backoff only when the callback reports
failure or throws.

### Clamp backoff before duration arithmetic

Clamp the exponential backoff exponent before shifting/multiplying, then apply
the configured maximum duration. This avoids overflow or zero-delay behavior
when an unavailable peer causes many retries.

## Risks / Trade-offs

- [Risk] A force-reconnect request may return immediately while pairing is in
  progress. → Expose the unavailable-peer diagnostic and leave the pairing
  listener untouched.
- [Risk] Creating separate socket managers can leave resources open if cleanup
  is incomplete. → Centralize client cleanup and add lifecycle tests for both
  listener and client paths.
- [Risk] Stricter callback result handling may alter retry timing. → Preserve
  the existing maximum delay and verify scheduler behavior with deterministic
  tests.

## Migration Plan

No data migration is required. Ship the facade/scheduler changes together,
run the automated QA suite, then verify pairing and reconnect on two Android
devices. Rollback is a code rollback only; persisted peer and self identities
remain compatible.
