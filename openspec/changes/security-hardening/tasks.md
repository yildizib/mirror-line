## 1. Security Foundations

- [x] 1.1 Add local database encryption key lifecycle management using
  Android Keystore-backed secure storage.
- [x] 1.2 Define centralized encryption, protocol version, freshness, frame,
  payload, queue, retry, and TTL constants.
- [x] 1.3 Add shared cryptographic helpers for local encryption, keyed lookup
  digests, canonical authenticated metadata, and safe failure handling.

## 2. Local Storage Migration

- [x] 2.1 Define the same-column versioned encryption format and migration
  contract for sensitive peer, call, SMS, notification, and queue data.
- [x] 2.2 Implement a resumable migration coordinator that initializes or
  recovers secure keys before transforming existing records.
- [x] 2.3 Encrypt existing sensitive records in place, verify successful
  decryption, and resume safely using the versioned storage prefix.
- [x] 2.4 Store the network AES key only as versioned local ciphertext in the
  existing peer key field while keeping secure storage authoritative.
- [x] 2.5 Add migration tests for fresh installs, upgrades, interruptions,
  missing secure keys, corrupt records, and repeatable execution.

## 3. DAO and Model Protection

- [x] 3.1 Update peer, call, SMS, notification, and queue persistence to encrypt
  sensitive fields in their existing columns before database writes.
- [x] 3.2 Update DAOs and queue handling to decrypt protected fields before
  returning application models or sending queued messages.
- [x] 3.3 Move address, thread, and package filtering/grouping after decryption
  without adding searchable sensitive columns.
- [x] 3.4 Preserve existing facade, provider, pagination, grouping, and UI
  behavior with decrypted model values.
- [x] 3.5 Add DAO regression tests proving plaintext is not persisted and UI
  models still contain the original readable values.

## 4. Offline Queue Protection

- [x] 4.1 Encrypt queue payloads with the local storage key before persistence
  and decrypt them only for network delivery.
- [x] 4.2 Enforce queue item count, item size, retry count, and retention TTL
  limits with a defined overflow and expiration policy.
- [x] 4.3 Prevent duplicate queue delivery using the originating message
  identity where applicable.
- [ ] 4.4 Add queue tests for encrypted persistence, delivery decryption,
  overflow, expiration, retry limits, and duplicate handling.

## 5. Authenticated Message Envelope

- [ ] 5.1 Add a versioned wire envelope without breaking controlled pairing
  compatibility.
- [ ] 5.2 Implement canonical authenticated metadata for protocol version,
  message type, message ID, and timestamp.
- [ ] 5.3 Include the canonical metadata as AES-GCM associated authenticated
  data for every encrypted normal message.
- [ ] 5.4 Reject unknown protocol versions, altered metadata, invalid payloads,
  and authentication failures before dispatching messages.
- [ ] 5.5 Add wire-level tests for valid envelopes, metadata tampering, wrong
  versions, wrong keys, and invalid ciphertext.

## 6. Mutual Peer Authentication

- [ ] 6.1 Extend the authentication transcript to include both device IDs,
  both expected public keys, fresh nonces, and the protocol version.
- [ ] 6.2 Require the server to verify the client Ed25519 signature and the
  client to verify the server Ed25519 signature.
- [ ] 6.3 Require both authentication proofs and the final acknowledgement
  before marking a paired connection ready.
- [ ] 6.4 Fail closed when an already paired connection lacks required identity
  material instead of silently skipping authentication.
- [ ] 6.5 Add authentication tests for valid peers, invalid signatures,
  identity mismatch, stale nonces, missing keys, timeout, and acknowledgement
  failure.

## 7. Session and Replay Protection

- [ ] 7.1 Generate and negotiate a fresh session identifier during every
  authenticated connection.
- [ ] 7.2 Add session ID, sequence data, and message ID handling to normal
  messages and queue delivery.
- [ ] 7.3 Reject messages from another session, duplicate IDs, invalid sequence
  values, and timestamps outside the freshness window.
- [ ] 7.4 Bound the accepted-message cache and clear it safely when a session
  ends.
- [ ] 7.5 Add replay tests for duplicate messages, cross-session messages,
  equal timestamps, stale timestamps, reordered delivery, and queue retries.

## 8. Secure Pairing

- [ ] 8.1 Bind QR, pairing request, pairing accept, verification data, and
  final acknowledgement to one peer identity transaction.
- [ ] 8.2 Include the expected public-key identities in verification value
  generation.
- [ ] 8.3 Reject pairing when peer ID, device identity, role, or public key
  changes unexpectedly during the transaction.
- [ ] 8.4 Keep pairing persistence atomic and prevent incomplete peer records
  after timeout or acknowledgement loss.
- [ ] 8.5 Add pairing tests for matching identities, public-key mismatch,
  peer-ID mismatch, verification mismatch, timeout, and atomic persistence.

## 9. Transport Resource Limits

- [ ] 9.1 Enforce maximum frame, JSON, and encrypted payload sizes before
  unbounded buffer growth or JSON decoding.
- [ ] 9.2 Close or reset connections that send oversized, malformed, or
  incomplete frames beyond the configured limits.
- [ ] 9.3 Add authentication connection timeout and invalid-message handling
  limits without weakening valid pairing behavior.
- [ ] 9.4 Add parser and transport tests for oversized frames, fragmented
  frames, malformed JSON, invalid UTF-8, and repeated invalid messages.

## 10. Documentation and Verification

- [ ] 10.1 Update the product document with the verified security behavior and
  remaining documented non-goals.
- [ ] 10.2 Add or update security tests covering raw wire confidentiality,
  local storage protection, migration, authentication, replay, pairing, and
  resource limits.
- [ ] 10.3 Run `dart format lib/ test/` and format any changed Dart files.
- [ ] 10.4 Run `dart analyze --fatal-infos` and fix all reported issues.
- [ ] 10.5 Run `flutter analyze` and fix all reported issues.
- [ ] 10.6 Run `flutter test` and verify all tests pass.
- [ ] 10.7 Run `flutter build apk --debug` and verify the debug APK builds.
- [ ] 10.8 Run OpenSpec validation and confirm all requirements have coverage.
