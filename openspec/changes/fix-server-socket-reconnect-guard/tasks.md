## 1. Reconnect and Socket Guards

- [x] 1.1 Add a single completed-remote-peer guard to all normal reconnect,
  force-connect, network-change, and fallback-scan entry points.
- [x] 1.2 Prevent unpaired network changes and manual reconnect requests from
  touching the temporary pairing listener.
- [x] 1.3 Separate outbound client socket ownership from pairing/server socket
  ownership and guarantee cleanup for both lifecycles.
- [x] 1.4 Make reconnect callbacks return explicit success/failure and ensure
  failed connection results cannot be treated as successful completion.
- [x] 1.5 Clamp exponential reconnect backoff before duration arithmetic so
  repeated failures never schedule a zero-second retry loop.

## 2. Regression Coverage

- [x] 2.1 Test that an unpaired network change preserves the pairing listener
  and starts neither reconnect nor subnet discovery.
- [x] 2.2 Test that manual force reconnect is a no-op with an unavailable
  remote peer and reports the appropriate diagnostic state.
- [x] 2.3 Test that a server-mode socket is never reused for an outbound client
  connection and that listener/client cleanup remains independent.
- [x] 2.4 Test scheduler success/failure callback handling and bounded retry
  delays, including high-attempt behavior.
- [x] 2.5 Run a two-device QR pairing flow followed by reconnect and network
  change verification on Android hardware.

## 3. Verification and Delivery

- [x] 3.1 Run `dart format lib/ test/` and format all changed Dart files.
- [x] 3.2 Run `dart analyze --fatal-infos` and fix all reported issues.
- [x] 3.3 Run `flutter analyze` and fix all reported issues.
- [x] 3.4 Run targeted connection, pairing, discovery, and scheduler tests.
- [x] 3.5 Run `flutter test` and verify all tests pass.
- [x] 3.6 Run `flutter build apk --debug`.
- [x] 3.7 Run strict OpenSpec validation and update the issue with each
  completed task commit before opening the PR.

## 4. Pairing Bootstrap Transport

- [x] 4.1 Separate QR bootstrap mode from authenticated paired transport and
  allow an unpaired listener to process a QR-authorized request.
- [x] 4.2 Keep pairing bootstrap out of normal connected-state side effects,
  queue flushing, and reconnect scheduling.
- [x] 4.3 Preserve fail-closed behavior for paired connections missing identity
  material.

## 5. Pairing Transaction State

- [x] 5.1 Initialize request and accept completion state and expected identity
  before sending the corresponding socket messages.
- [x] 5.2 Check request, accept, acknowledgement, and rejection write results;
  do not report failed writes as delivered or complete.
- [x] 5.3 Validate `pairingAck` against the pending scanner transaction and
  remote identity, then clear transaction state on every terminal outcome.

## 6. Pairing Endpoint and Identity Safety

- [x] 6.1 Reject QR endpoints that are empty, invalid, loopback, or present in
  the scanner's complete local-IP inventory before opening a socket.
- [x] 6.2 Validate claimed request and accept IPs before persisting them and add
  diagnostics for locally-owned or stale endpoints.
- [ ] 6.3 Generate QR and pairing response identity from local self identity,
  not the overloaded remote peer record.
- [ ] 6.4 Prevent the UI from presenting QR data with missing, placeholder, or
  stale local identity fields.

## 7. Socket Lifecycle and Diagnostics

- [ ] 7.1 Bind socket completion and error handling to the socket instance so
  stale callbacks cannot close a replacement socket.
- [ ] 7.2 Log incoming remote address, outgoing target, transport mode, and
  stage-specific pairing failures without logging secrets.

## 8. Pairing Regression Coverage

- [ ] 8.1 Test fresh Main-to-Source and Source-to-Main request, accept, ack,
  persistence, and authenticated reconnect flows.
- [ ] 8.2 Test immediate accept and ack responses, disconnect races, failed
  writes, and stale socket callbacks.
- [ ] 8.3 Test self-endpoint QR, loopback, stale claimed IP, mixed identity, and
  unavailable QR-field scenarios.

## 9. Verification and Delivery

- [ ] 9.1 Run `dart format lib/ test/`.
- [ ] 9.2 Run `dart analyze --fatal-infos`.
- [ ] 9.3 Run `flutter analyze`.
- [ ] 9.4 Run targeted pairing, socket, connection, discovery, and scheduler
  tests.
- [ ] 9.5 Run `flutter test`.
- [ ] 9.6 Run `flutter build apk --debug`.
- [ ] 9.7 Run two-way QR pairing, reconnect, and network-change QA on two
  Android devices.
- [ ] 9.8 Run strict OpenSpec validation and update Issue #98 per task commit
  before opening the PR.
