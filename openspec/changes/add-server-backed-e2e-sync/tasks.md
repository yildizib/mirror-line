## T1. Contracts and OpenSpec foundation

- [x] 1.1 Define target server-mediated product boundaries and canonical IDs.
- [x] 1.2 Define cryptographic envelope, replay, pairing, rotation, retention,
  session, audit, API, error, documentation, and 97-screen contracts.
- [x] 1.3 Validate OpenSpec and the documentation manifest.

## T2. Interoperable cryptography

- [ ] 2.1 Implement Ed25519, X25519, HKDF-SHA256, AES-256-GCM, RFC 8785, and
  versioned fixture contracts in shared/mobile/server modules.
- [ ] 2.2 Add cross-language positive, tamper, canonicalization, and key-version
  interoperability tests.

## T3. Persistence and migrations

- [ ] 3.1 Add Flyway migrations and explicit `JdbcTemplate` SQL repositories
  for accounts, devices, public keys, pairing, opaque mailbox,
  acknowledgements, sessions, and append-only audit records.
- [ ] 3.2 Add mobile persistence for identities, public-key versions, mailbox
  cursors, encrypted envelopes, eight-day replay records, and history policy.
- [ ] 3.3 Test PostgreSQL constraints, concurrent quota transitions, upgrades,
  expiry cleanup, idempotency, and retention boundaries without JPA.

## T4. Identity and device registration

- [ ] 4.1 Implement server-generated UUIDv4 users/devices and canonical device
  identity enforcement.
- [ ] 4.2 Implement authenticated device registration, one-Main/five-Source
  limits, revocation, and session semantics.
- [ ] 4.3 Expose facade-only mobile identity/device flows with tests.

## T5. Server-mediated pairing

- [ ] 5.1 Implement five-minute, one-use code issue/redeem/cancel/status APIs.
- [ ] 5.2 Implement signed proofs, comparison confirmation, atomic membership,
  terminal state handling, and pairing audit events.
- [ ] 5.3 Add server, mobile, and cross-network integration coverage.

## T6. Key rotation and recovery

- [ ] 6.1 Implement 90-day scheduling, manual rotation, emergency rotation, and
  local private-key protection.
- [ ] 6.2 Implement dual old/new proof, peer acknowledgements, 24-hour
  activation, 14-day overlap, recovery, and key lifecycle audit events.
- [ ] 6.3 Add clocks, offline-peer, revocation, and downgrade-rejection tests.

## T7. Security audit and sessions

- [ ] 7.1 Implement append-only redacted security events and one-year retention.
- [ ] 7.2 Implement active-session, last-login, revoke, and sign-out behavior.
- [ ] 7.3 Add authorization, redaction, immutability, and retention tests.

## T8. Encrypted relay mailbox

- [ ] 8.1 Implement authenticated envelope admission, seven-day opaque mailbox,
  idempotent delivery acknowledgements, and recipient authorization.
- [ ] 8.2 Implement mobile envelope send/pull/ack facades without UI direct
  access to base services.
- [ ] 8.3 Add signature, replay, expiry, delivery, and ciphertext-only tests.

## T9. Push and scheduled jobs

- [ ] 9.1 Implement content-free push wake signals and delivery retry policy.
- [ ] 9.2 Implement mailbox, replay, audit, session, and key-overlap jobs.
- [ ] 9.3 Test job idempotency, observability, failure recovery, and no-content
  push guarantees.

## T10. Mobile account and session foundations

- [ ] 10.1 Implement account, verified-session, device-registration, and
  security-session facade contracts.
- [ ] 10.2 Add local state, failure mapping, secure token handling, and tests.

## T11. Mobile pairing and device management foundations

- [ ] 11.1 Implement pairing and device facades plus source/main capacity state.
- [ ] 11.2 Implement comparison, rejection, expiry, and re-pair recovery state.

## T12. Mobile key and relay foundations

- [ ] 12.1 Implement mobile key lifecycle, encrypted outbox/inbox, replay, and
  relay synchronization facades.
- [ ] 12.2 Add offline, retry, rotation, and security error state tests.

## T13. Mobile security, history, and diagnostics foundations

- [ ] 13.1 Implement session, audit, local-history selection, and safe
  diagnostics facade contracts.
- [ ] 13.2 Ensure redaction and UI-service boundary tests pass.

## T14. Approved mobile UI

- [ ] 14.1 Implement the approved 97-screen flow, including A12-A14, R08, P17,
  SS10, and X09, through UI services only.
- [ ] 14.2 Add widget/integration coverage for success, failure, accessibility,
  Turkish, and English states.

## T15. Legacy LAN/VPN removal

- [ ] 15.1 Remove UDP beacon, subnet scanning, direct TCP/VPN discovery,
  LAN-only pairing payloads, and legacy reconnect paths after parity.
- [ ] 15.2 Migrate or retire legacy records safely and add regression tests.

## T16. Operations and deployment

- [ ] 16.1 Add production configuration, health/metrics, backup/restore,
  retention monitoring, and incident runbooks without secrets in source.
- [ ] 16.2 Validate server image, Compose, TLS path, and database operations.

## T17. Acceptance and release evidence

- [ ] 17.1 Run all applicable mobile, server, infrastructure, OpenSpec, and
  Graphify checks.
- [ ] 17.2 Complete physical two-device tests across independent networks,
  pairing, rotation, replay, expiry, recovery, and accessibility flows.
- [ ] 17.3 Reconcile product documentation and obtain review before release.
