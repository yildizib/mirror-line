## 1. Production storage migration

- [x] 1.1 Identify the production database bootstrap boundary.
- [x] 1.2 Invoke `LocalStorageMigrationCoordinator.migrate` exactly once per
  startup/database lifecycle, with retry-safe error handling.
- [ ] 1.3 Add startup integration coverage for migration, interruption, retry,
  and unavailable secure storage.

## 2. Socket subscription lifecycle

- [x] 2.1 Store the active stream subscription and associated socket identity.
- [x] 2.2 Cancel matching subscriptions during replacement, disconnect, and
  disposal.
- [x] 2.3 Add tests for replacement, stale callbacks, disconnect, and dispose.

## 3. Settings architecture

- [x] 3.1 Add UI-facing methods for native Settings operations.
- [x] 3.2 Remove direct `TelephonyChannel` calls from `settings_screen.dart`.
- [x] 3.3 Replace the top-level whole-state `ConnectionStatus` watch with
  field selects.
- [ ] 3.4 Add tests proving Settings actions use the UI service boundary and
  unrelated status changes do not rebuild sections.

## 4. Documentation and verification

- [x] 4.1 Update Turkish and English product documentation for schema version
  7 and `offline_queue.dedupe_key`.
- [x] 4.2 Clarify stored multiple peers versus the single active runtime peer.
- [x] 4.3 Add deterministic format/OpenSpec validation to CI as appropriate.
- [x] 4.4 Record automated versus manual/device-only acceptance coverage.

## 5. Verification

- [ ] 5.1 Run formatting, analyzers, focused tests, and the full test suite.
- [ ] 5.2 Run debug APK build verification.
- [ ] 5.3 Validate this OpenSpec change and update issue #105 with evidence.
