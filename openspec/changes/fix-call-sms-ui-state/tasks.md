## 1. Call UI State

- [x] 1.1 Add regression coverage for same-identifier call status replacement,
  grouping-key movement, and Reject action targeting; update call pagination
  reconciliation so a missed call replaces stale ringing state and only the
  active ringing call remains rejectable; run the focused call tests and
  analyzers.

## 2. SMS Sending State

- [x] 2.1 Add regression coverage for same-identifier `pending` to `sent` and
  `failed` replacement in both SMS list and detail providers; make fresh SMS
  records authoritative and await optimistic persistence before transmission;
  run the focused SMS state tests and analyzers.

## 3. SMS Thread Navigation

- [ ] 3.1 Add regression coverage for initial loading, confirmed-empty
  handling, and one-tap thread navigation; track initial-load completion and
  revalidate deferred route closure against live provider state; run the
  focused SMS widget and provider tests and analyzers.

## 4. Verification

- [ ] 4.1 Run `dart format lib/ test/`, `dart analyze --fatal-infos`,
  `flutter analyze`, the complete `flutter test` suite, strict OpenSpec
  validation, and `flutter build apk --debug`; resolve every failure before
  marking the change implementation complete.
