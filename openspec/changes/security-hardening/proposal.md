## Why

MirrorLine currently encrypts message payloads with AES-256-GCM, but several
security-sensitive areas remain insufficiently protected. Local databases and
offline queues may expose sensitive data, peer authentication is not fully
mutual, replay protection is incomplete, and message metadata is not covered
by authenticated encryption.

This change is needed before MirrorLine can make a strong end-to-end security
claim.

## What Changes

- Encrypt sensitive SQLite fields at rest using a local encryption key stored
  in Android Keystore-backed secure storage.
- Remove plaintext storage of the network AES key from SQLite.
- Encrypt offline queue payloads before persisting them.
- Add authenticated message envelopes using GCM associated authenticated data
  for message metadata.
- Add mutual Ed25519 peer authentication.
- Bind pairing verification to the expected device identity and public key.
- Add session-aware replay protection using message IDs, timestamps, and
  sequence data.
- Add TCP frame, payload, queue size, and queue TTL limits.
- Add database migration support for existing plaintext records.
- Add security regression, migration, replay, authentication, and resource
  limit tests.
- Update product security documentation after the implementation is verified.

## Capabilities

### New Capabilities

- `secure-local-storage`: Protect sensitive SQLite records, network keys, and
  offline queue payloads at rest.
- `authenticated-peer-transport`: Provide authenticated message envelopes,
  mutual peer authentication, replay protection, and transport resource
  limits.
- `secure-pairing`: Bind pairing confirmation to the expected peer identity
  and Ed25519 public key.

### Modified Capabilities

None.

## Impact

- Affected Dart code includes database models, DAOs, migrations, secure
  storage, cryptography, queue handling, message protocol, socket management,
  pairing, and connection facades.
- Android Keystore-backed storage will hold an additional local database
  encryption key.
- The wire protocol will receive a versioned authenticated envelope.
- Existing local databases require an upgrade migration.
- Existing security and integration tests must be extended.
- No new external server or cloud dependency will be introduced.
- The user-visible product behavior remains the same, but local data and
  device-to-device communication receive stronger protection.
