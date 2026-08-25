## Context

The current runtime has a temporary pairing socket in `PairingFacade`, while
`ConnectionFacade` owns the long-lived peer socket, reconnect scheduler, beacon
listener, and fallback subnet scanner. Device logs show that the temporary QR
connection can succeed while a stale normal reconnect still targets the local
IP and the fallback scanner receives port `0` during an unpaired state.

## Goals / Non-Goals

**Goals:**

- Make pairing, normal connection, and discovery explicit mutually compatible
  runtime states.
- Stop self-connections and invalid scans before they reach `Socket`.
- Preserve the existing QR wire format and mutual authentication behavior.
- Keep peer identity persistence atomic and remote-only.
- Provide safe diagnostics for real-device testing.

**Non-Goals:**

- Redesign the QR payload format.
- Add a relay or internet-based pairing path.
- Change cryptographic algorithms or weaken authentication.
- Add database columns or migrate existing stored data.

## Decisions

### 1. Gate discovery at the ConnectionFacade boundary

The facade will decide whether the device is paired and whether an endpoint is
usable before invoking `ReconnectScheduler`, `PeerDiscoveryCoordinator`, or
`SubnetScanner`. This keeps lower-level utilities reusable while preventing
port `0` and unpaired work from being scheduled.

Alternative rejected: relying only on callers to provide valid values, because
the periodic health timer and network-change callbacks can independently start
discovery.

### 2. Invalidate asynchronous work with a generation/state guard

Pairing start, pairing reset, and unpaired refresh will invalidate pending
reconnect and discovery continuations. Existing generation guards will be
extended rather than adding another competing socket lifecycle.

Alternative rejected: only cancelling timers, because an already-running scan
or socket attempt can continue after a timer is cancelled.

### 3. Validate local identity at the pairing facade boundary

The pairing facade will compare incoming and QR-bound identity material with
the local device identity before persistence or success state transitions. The
peer facade will retain a final defensive check so callers cannot create a
self-peer record accidentally.

Alternative rejected: filtering only in Settings, because self-peer data would
still affect connection attempts and discovery.

### 4. Preserve the temporary pairing socket

The QR handshake will continue using its dedicated `SocketManager`; normal
connection machinery will be paused or ignored during the transaction. This
avoids changing the already successful TCP and encrypted request path.

## Risks / Trade-offs

- [Risk] A pairing transaction may outlive a network transition. → Invalidate
  the transaction cleanly and show a stage-specific retry error.
- [Risk] Existing paired records may have incomplete identity fields. → Treat
  them as not eligible for automatic authenticated reconnect and report the
  missing identity without deleting data.
- [Risk] Discovery guards could suppress valid post-pairing reconnects. → Add
  paired/unpaired unit tests and retain the existing successful reconnect tests.
- [Risk] Device logs may expose too much pairing context. → Log IDs only in
  shortened/non-secret form and never log keys or decrypted payloads.

## Migration Plan

No storage migration is expected. Existing records remain readable; records
without a valid remote identity are treated as unpaired until a new QR pairing
completes.
