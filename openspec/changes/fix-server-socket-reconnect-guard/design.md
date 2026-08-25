## Context

See `proposal.md` for the observed failure. The connection facade owns pairing
listener and normal peer socket lifecycles, while reconnect triggers can arrive
from timers, network events, manual actions, and discovery callbacks. QR
pairing also owns a temporary outbound socket. Device logs show the bootstrap
path is rejected by the paired-auth fail-closed guard before
`pairing_request` is processed.

The pairing transaction has independent request, accept, and acknowledgement
completers, claimed IP values, and persistence gates. These values must remain
consistent when responses arrive quickly or a socket is replaced during retry.

## Goals / Non-Goals

**Goals:**

- Make completed remote identity the single prerequisite for normal reconnect
  and fallback discovery.
- Keep pairing listener ownership separate from outbound client ownership.
- Make scheduler failure handling and backoff deterministic and bounded.
- Allow only QR-authorized bootstrap traffic before a remote paired identity
  exists and keep normal application traffic out of that mode.
- Reject QR endpoints that identify the scanning device itself.
- Complete pairing only after both sides validate the same transaction and
  remote identity.
- Keep local identity data separate from the remote peer record.

**Non-Goals:**

- Redesign the QR payload or pairing handshake protocol.
- Change peer persistence schema.
- Add a new networking dependency.
- Change source-role telephony or beacon semantics beyond protecting their
  listener lifecycle.
- Redesign cryptographic algorithms, the QR wire format, or persistence schema.

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

### Treat QR bootstrap as a distinct transport mode

An unpaired listener will not require a remote public key that cannot exist
yet. It can process only a transaction authorized by the QR-derived secret and
will not trigger normal connected-state side effects. Once pairing commits,
subsequent peer transport requires the complete mutual identity.

Alternative considered: treat every socket without a public key as pairing
mode. Rejected because an already paired record with missing identity must fail
closed rather than silently downgrade.

### Initialize pairing state before socket writes

Request and acknowledgement completers and expected transaction identity will
be created before the corresponding write. Every pairing write result will be
checked. A fast response or failed write therefore becomes an immediate state
transition instead of a later timeout.

Alternative considered: rely on TCP ordering and timeout recovery. Rejected
because a local write can complete while the peer has already closed, producing
a misleading delivered state.

### Validate claimed endpoints before persistence

QR and pairing messages may carry a claimed local IP, but loopback, invalid,
and locally-owned endpoints will be rejected. Live TCP remote information will
be retained as a validated fallback and diagnostic rather than allowing an
untrusted stale claim to persist the receiver's own address.

A valid non-local claim remains preferred so existing VPN and multi-network
routing continues to work. A difference from the live TCP address is surfaced
as a stale-candidate diagnostic but is not sufficient by itself to reject the
claim; unsafe claims fall back to the validated live address.

Alternative considered: persist every claimed IP without validation for
NAT/VLAN support. Rejected because unsafe claims can create self-endpoint peer
records.

### Bind callbacks to socket ownership

Completion and error handlers will affect only the socket instance that created
them. A delayed callback from a replaced socket cannot close or mark the new
socket disconnected.

Alternative considered: rely on socket destruction ordering. Rejected because
stream callbacks can arrive after replacement ownership has changed.

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
- [Risk] Rejecting stale or locally-owned claims may affect unusual network
  topologies. → Prefer validated live endpoint data and expose a stage-specific
  diagnostic instead of persisting an unsafe endpoint.
- [Risk] Removing normal connection side effects from bootstrap can expose
  hidden coupling. → Cover complete request/accept/ack and post-pair reconnect
  flows in tests and two-device QA.

## Migration Plan

No data migration is required. Existing records remain readable. Records
without a valid remote identity remain unpaired, while records whose peer IP is
locally owned are rejected for reconnect and require rediscovery or re-pairing.
Ship the facade, pairing, and socket changes together, run the automated QA
suite, then verify pairing and reconnect on two Android devices. Rollback is a
code rollback only; persisted peer and self identities remain compatible.
