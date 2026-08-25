## Why

After pairing-runtime discovery and transport hardening were merged, device
logs exposed a broader QR pairing failure. An unpaired listener is marked as
requiring paired authentication before a remote identity exists, so it closes
the incoming QR socket before processing `pairing_request`. Pairing
acknowledgement, endpoint selection, and socket callback gaps can then leave
the devices in different pairing states.

## What Changes

- Prevent unpaired devices from starting normal reconnect or subnet discovery
  after network changes or manual reconnect requests.
- Keep the temporary pairing server socket isolated from normal client
  reconnects.
- Make reconnect scheduling preserve a bounded backoff and treat failed
  connection results as failures.
- Keep QR bootstrap transport separate from authenticated paired transport and
  prevent normal connection side effects during pairing.
- Validate QR endpoints against all local addresses and preserve local versus
  remote identity semantics in QR data and pairing responses.
- Make request, accept, acknowledgement, disconnect, and persistence
  transitions deterministic under fast responses and failed writes.
- Prevent stale socket callbacks from closing replacement connections.
- Add full request/accept/ack and self-endpoint regression coverage.
- Verify two-way QR pairing, reconnect, and network changes on Android devices.

## Capabilities

### New Capabilities

- `server-socket-reconnect`: Defines safe socket ownership and reconnect
  behavior while pairing is incomplete or a peer is disconnected, including
  QR bootstrap isolation and stale callback handling.

### Modified Capabilities

<!-- No existing main capability specs are present in this repository. -->

## Impact

- Affects `ConnectionFacade`, `PairingFacade`, pairing UI services,
  `SocketManager`, endpoint validation, and reconnect coordination.
- Adds connection and pairing regression tests.
- Does not change cryptographic algorithms, pairing payload format, storage
  schema, or dependencies.
