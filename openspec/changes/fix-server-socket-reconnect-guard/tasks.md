## 1. Reconnect and Socket Guards

- [ ] 1.1 Add a single completed-remote-peer guard to all normal reconnect,
  force-connect, network-change, and fallback-scan entry points.
- [ ] 1.2 Prevent unpaired network changes and manual reconnect requests from
  touching the temporary pairing listener.
- [ ] 1.3 Separate outbound client socket ownership from pairing/server socket
  ownership and guarantee cleanup for both lifecycles.
- [ ] 1.4 Make reconnect callbacks return explicit success/failure and ensure
  failed connection results cannot be treated as successful completion.
- [ ] 1.5 Clamp exponential reconnect backoff before duration arithmetic so
  repeated failures never schedule a zero-second retry loop.

## 2. Regression Coverage

- [ ] 2.1 Test that an unpaired network change preserves the pairing listener
  and starts neither reconnect nor subnet discovery.
- [ ] 2.2 Test that manual force reconnect is a no-op with an unavailable
  remote peer and reports the appropriate diagnostic state.
- [ ] 2.3 Test that a server-mode socket is never reused for an outbound client
  connection and that listener/client cleanup remains independent.
- [ ] 2.4 Test scheduler success/failure callback handling and bounded retry
  delays, including high-attempt behavior.
- [ ] 2.5 Run a two-device QR pairing flow followed by reconnect and network
  change verification on Android hardware.

## 3. Verification and Delivery

- [ ] 3.1 Run `dart format lib/ test/` and format all changed Dart files.
- [ ] 3.2 Run `dart analyze --fatal-infos` and fix all reported issues.
- [ ] 3.3 Run `flutter analyze` and fix all reported issues.
- [ ] 3.4 Run targeted connection, pairing, discovery, and scheduler tests.
- [ ] 3.5 Run `flutter test` and verify all tests pass.
- [ ] 3.6 Run `flutter build apk --debug`.
- [ ] 3.7 Run strict OpenSpec validation and update the issue with each
  completed task commit before opening the PR.
