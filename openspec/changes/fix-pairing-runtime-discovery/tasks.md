## 1. Runtime State Guards

- [x] 1.1 Define the paired, unpaired, pairing-pending, and pairing-complete
  runtime conditions at the facade boundary.
- [x] 1.2 Prevent reconnect scheduling and fallback discovery for unpaired
  devices, invalid endpoints, and zero-port scans.
- [x] 1.3 Cancel or invalidate stale reconnect, scan, and network-change work
  when pairing starts, resets, times out, or completes.
- [x] 1.4 Add tests proving unpaired devices never connect to their own IP or
  invoke subnet discovery with port `0`.

## 2. Pairing Identity Safety

- [x] 2.1 Validate QR-bound device ID and public key against the local identity
  before starting the pairing transaction.
- [x] 2.2 Reject incoming pairing requests and persistence updates that claim
  the local device as the remote peer.
- [x] 2.3 Preserve the dedicated temporary pairing socket while pausing normal
  connection machinery during the transaction.
- [x] 2.4 Add pairing tests for valid remote identities, self identity, identity
  mismatch, timeout, and retry after reset.

## 3. Peer Presentation and Diagnostics

- [x] 3.1 Ensure self-only setup records are not presented as paired remote
  devices in Settings or connection status.
- [x] 3.2 Ensure completed pairing persists the other device's identity and
  endpoint on both devices without replacing it with local identity data.
- [x] 3.3 Add non-secret stage diagnostics for QR parsing, TCP connection,
  request delivery, accept, acknowledgement, and rejection paths.
- [x] 3.4 Add regression coverage for Settings-facing peer state and diagnostic
  states after successful and failed pairing.

## 4. Verification

- [x] 4.1 Run `dart format lib/ test/` and format changed Dart files.
- [ ] 4.2 Run `dart analyze --fatal-infos` and fix all reported issues.
- [ ] 4.3 Run `flutter analyze` and fix all reported issues.
- [ ] 4.4 Run targeted pairing, connection, discovery, and peer tests.
- [ ] 4.5 Run `flutter test` and verify all tests pass.
- [ ] 4.6 Run `flutter build apk --debug`.
- [ ] 4.7 Run OpenSpec validation and complete a two-device QR pairing test.
