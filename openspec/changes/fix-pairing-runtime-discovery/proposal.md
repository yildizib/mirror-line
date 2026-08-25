## Why

Real-device pairing reaches the scanned phone and sends `pairing_request`, but
the runtime also starts ordinary reconnect and fallback discovery while the
device is still unpaired. This causes self-address connection attempts, scans
on port `0`, misleading peer records in Settings, and can interrupt the QR
handshake before the other device completes it.

## What Changes

- Gate reconnect, beacon, and fallback subnet discovery on a completed pairing
  state and a valid peer port.
- Cancel stale reconnect attempts when pairing starts, pairing completes, or a
  device is reset to the unpaired state.
- Keep the temporary QR handshake isolated from the normal connection socket.
- Reject self-device identities during QR request and peer persistence flows.
- Prevent Settings and peer state from presenting the local device as its own
  paired peer.
- Add pairing/runtime diagnostics and two-device regression coverage.

## Capabilities

### New Capabilities

- `pairing-runtime-discovery`: Keeps QR pairing, peer identity persistence, and
  automatic network discovery in separate, valid runtime states.

### Modified Capabilities

None.

## Impact

- `ConnectionFacade`, `ReconnectScheduler`, and peer discovery coordination.
- QR pairing UI/facade and peer persistence boundary.
- Pairing, connection, discovery, and Settings-facing regression tests.
- No new dependencies or database schema changes are expected.
