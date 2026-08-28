## 1. Identity and discovery

- [x] 1.1 Add tests proving discovery/broadcast never uses the remote peer ID as
  the local ID.
- [x] 1.2 Implement one facade-level local identity resolver and persist a
  generated self ID/name before starting discovery or source broadcasting.
- [x] 1.3 Update all connection entry points to use the resolver and preserve
  the expected remote peer ID check.

## 2. Storage and display recovery

- [x] 2.1 Add DAO/crypto tests for valid values, legacy values, and
  double-encrypted `v1:` values.
- [x] 2.2 Implement safe lazy repair or invalid-record handling for peer
  display fields without changing key encryption or schema.
- [x] 2.3 Ensure Settings renders a human-readable fallback and never exposes
  ciphertext, public keys, or secret material as a device name.

## 3. Endpoint and reconnect recovery

- [x] 3.1 Add tests for accepting a validated authenticated endpoint change and
  rejecting unauthenticated identity changes.
- [x] 3.2 Persist the accepted current endpoint and invalidate stale retries
  targeting the old address.
- [x] 3.3 Add regression coverage for beacon races, socket replacement, and
  the disconnected/loading UI state.

## 4. Verification and delivery

- [x] 4.1 Run `dart format lib/ test/`.
- [x] 4.2 Run `dart analyze --fatal-infos` and `flutter analyze`.
- [x] 4.3 Run targeted identity, storage, discovery, connection, and Settings
  tests, then `flutter test`.
- [x] 4.4 Run `flutter build apk --debug`; physical-device recovery
  verification remains pending.
- [ ] 4.5 Validate this OpenSpec change and update Issue #110 with evidence;
  implementation commits, if approved later, must start with `#110:`.
