## Why

After pairing-runtime discovery was merged, device logs exposed a reconnect
regression: an unpaired Main device can keep its temporary pairing server open
while a network-change or force-reconnect path attempts to reuse that server as
a client. The result is a rejected connection attempt and, after enough
failures, a tight reconnect loop with no useful backoff.

## What Changes

- Prevent unpaired devices from starting normal reconnect or subnet discovery
  after network changes or manual reconnect requests.
- Keep the temporary pairing server socket isolated from normal client
  reconnects.
- Make reconnect scheduling preserve a bounded backoff and treat failed
  connection results as failures.
- Add regression tests for server/client socket ownership and retry behavior.
- Verify the fix on Android devices with a two-device QR pairing flow.

## Capabilities

### New Capabilities

- `server-socket-reconnect`: Defines safe socket ownership and reconnect
  behavior while pairing is incomplete or a peer is disconnected.

### Modified Capabilities

<!-- No existing main capability specs are present in this repository. -->

## Impact

- Affects `ConnectionFacade`, `ReconnectScheduler`, and socket lifecycle
  coordination.
- Adds connection and pairing regression tests.
- Does not change the pairing protocol payload or require new dependencies.
