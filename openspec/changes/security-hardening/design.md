## Context

MirrorLine currently uses AES-256-GCM for network payloads and stores peer
material, message records, and offline queue data in SQLite. The existing
protocol authenticates the client to the server, but does not fully bind
message metadata, authenticate both peer identities, or reject all replay
classes. Existing local records also contain sensitive plaintext fields.

This design implements the behavior defined in the three capability specs:
`secure-local-storage`, `authenticated-peer-transport`, and `secure-pairing`.

## Goals / Non-Goals

**Goals:**

- Protect sensitive local records without changing the user-visible message
  experience.
- Keep the network encryption key and local storage encryption key separate.
- Migrate existing installations without silently losing user data.
- Authenticate message metadata as part of the encrypted message contract.
- Require both paired devices to prove their expected Ed25519 identities.
- Reject replayed messages and bound network and queue resource usage.
- Keep the implementation inside the existing `core -> facade -> UI` layering.

**Non-Goals:**

- Replacing SQLite with SQLCipher in this change.
- Adding a cloud service, relay server, or remote backup system.
- Adding TLS as a second transport encryption layer.
- Providing forward secrecy through a new key agreement protocol.
- Changing the existing user-facing calls, SMS, notification, or pairing flows
  beyond their security validation behavior.

## Decisions

### Application-level local encryption instead of SQLCipher

Sensitive values will be encrypted at the application layer with AES-256-GCM.
SQLite remains the storage engine. This avoids a platform-specific SQLCipher
migration while still preventing readable sensitive values in the database.

The alternative was SQLCipher database-wide encryption. It would protect all
columns automatically, but would add native build and migration complexity and
would not remove the need for a secure database-key lifecycle. Application-level
encryption is preferred because the current DAOs already define the storage
boundary and can preserve the existing database format incrementally.

### Separate local and network keys

A new random 256-bit local storage key will be generated once and stored only in
`flutter_secure_storage`, backed by Android Keystore. It will be distinct from
the peer network AES key and the Ed25519 identity keys.

The network AES key will no longer be relied on as a readable SQLite value. The
secure storage copy remains authoritative. The legacy database column will be
cleared only after the secure storage value has been verified.

### Column-level encrypted storage with lookup hashes

Encrypted columns will be added for sensitive values rather than replacing
existing columns immediately. The migration will write the encrypted value,
verify it can be decrypted, and then replace the legacy plaintext value with an
empty sentinel where the schema requires a non-null value.

Call numbers, SMS addresses, and notification package names sometimes need
grouping or lookup. The system will store a keyed lookup digest alongside the
ciphertext. The digest will be derived with the local storage key and will not
be a plain SHA-256 of the sensitive value. Message bodies, titles, and contact
names will not receive searchable plaintext copies.

DAOs will decrypt values before returning models to facades. Facades and UI
components will continue to consume normal readable model values and will not
know whether a field was encrypted at rest.

### Resumable database migration

The current schema version 6 will be upgraded with a new migration version.
Because secure storage access is asynchronous and the SQLite upgrade callback
is not the right place for the complete data transformation, schema changes and
data migration will be separated:

1. Add encrypted and lookup columns in the SQLite schema migration.
2. Initialize or recover the local storage key through secure storage.
3. Convert existing records in bounded transactions.
4. Verify encrypted values and lookup digests.
5. Scrub legacy plaintext values and the legacy peer key column.
6. Persist a migration marker only after all records are complete.

If secure storage is unavailable, the migration will stop before destructive
scrubbing. If interrupted, the marker and per-record state allow the operation
to resume without duplicating records or losing the original recoverable data.

### Encrypt the offline queue before persistence

Queue payloads will be encrypted with the local storage key before insertion.
When delivery resumes, the queue service will decrypt the local payload and pass
the plaintext only to the network sender, which will apply the network message
encryption before transmission.

Queue metadata will include bounded retry and age handling. Initial limits will
be centralized constants: a maximum frame and payload size, a maximum queue item
count, a maximum item size, a maximum retry count, and a queue item TTL. Values
will be covered by tests and can be tuned without changing the wire contract.

### Versioned authenticated message envelope

The wire envelope will include a protocol version and use a canonical encoding
of the version, type, ID, and timestamp as AES-GCM associated authenticated data.
The encrypted payload and this metadata will therefore be cryptographically
bound together.

Conceptually:

```text
aad = canonical(version, type, id, timestamp)
ciphertext = AES-GCM.encrypt(payload, key, aad)
```

The receiver will reconstruct the exact same AAD before decryption. Any change
to the envelope metadata will fail authentication. Unknown protocol versions
will be rejected rather than interpreted as the current format.

### Mutual Ed25519 authentication

The existing client-signs-server-challenge flow will become a mutual
challenge-response handshake. Both devices will sign a transcript containing
the session nonces, both device IDs, both expected public keys, and the
protocol version.

The server will verify the client signature and the client will verify the
server signature. The connection will not be marked ready until both proofs and
the final acknowledgement succeed. The pairing bootstrap path may remain
temporarily unauthenticated only while the user-approved pairing transaction is
using the QR-derived pairing secret; an already paired connection with missing
identity material will fail closed instead of silently falling back.

### Session-bound replay protection

Each authenticated connection will receive a fresh session identifier. Messages
will carry the session identifier, a sequence value, a timestamp, and a unique
message ID. The receiver will maintain a bounded set of accepted IDs for the
active session and will reject:

- Messages from a different session.
- Duplicate message IDs.
- Messages outside the configured freshness window.
- Invalid or regressing sequence values according to the delivery policy.

The accepted ID set will be bounded to avoid turning replay protection into an
unbounded memory allocation. This change does not introduce forward secrecy;
that is an explicit non-goal.

### Public-key-bound pairing

Pairing identity data will be treated as one transaction. The peer ID, device
identity, role, and Ed25519 public key received through QR and pairing messages
must remain consistent through request, accept, verification, and final ack.

The verification value will include the pairing secret, both peer identities,
and the expected public-key identities. A changed public key will therefore
produce a different verification value and will not be silently accepted.
Persistence remains gated on the final acknowledgement.

### Bounded transport parsing

The socket parser will enforce maximum frame and payload sizes before growing the
receive buffer or decoding JSON. Invalid, incomplete, oversized, or malformed
frames will be rejected and the offending connection will be closed or reset.
Queue count, item size, retry count, and item age will be bounded by the same
policy layer.

## Risks / Trade-offs

- **[Risk] Existing records may be large or partially corrupt.**
  **Mitigation:** Migrate in bounded transactions, keep a resumable marker, and
  validate each encrypted value before scrubbing its legacy value.

- **[Risk] Application-level encryption leaves non-sensitive metadata visible.**
  **Mitigation:** Keep only required IDs, status, direction, and timestamps
  readable; bind all network envelope metadata with GCM AAD.

- **[Risk] Keyed lookup hashes reveal equality of repeated values.**
  **Mitigation:** Use a device-local secret key, never a public hash, and limit
  lookup hashes to fields that require grouping.

- **[Risk] Missing secure storage could block startup after migration begins.**
  **Mitigation:** Fail closed before destructive cleanup and keep migration
  state retryable.

- **[Risk] Mutual authentication may reject legacy paired installations.**
  **Mitigation:** Add an explicit protocol version and controlled re-pairing or
  identity upgrade path; do not silently downgrade an already paired session.

- **[Risk] Tight frame and queue limits may reject unusually large valid data.**
  **Mitigation:** Centralize limits, expose controlled failure states, and cover
  boundary values with tests.

- **[Risk] No TLS or forward secrecy is added.**
  **Mitigation:** Document this limitation and ensure application-level
  encryption, mutual identity authentication, and metadata authentication are
  complete before making security claims.

## Migration Plan

1. Ship the new schema columns and local-key initialization code.
2. On first launch after the update, run the resumable local-data migration.
3. Verify encrypted records and secure storage before scrubbing legacy values.
4. Enable the versioned authenticated envelope for new connections.
5. Require the upgraded mutual authentication handshake for paired sessions.
6. If a peer cannot complete the new handshake, show a controlled re-pairing
   requirement instead of falling back to unauthenticated normal traffic.
7. After successful migration and protocol verification, remove compatibility
   reads of legacy plaintext fields in a later cleanup change.

Rollback is limited to application version rollback. The migration must retain
enough version markers and encrypted columns for the previous application to
fail safely rather than misinterpret the new format. A database backup or
explicit recovery path must be validated before destructive cleanup is enabled.

## Open Questions

None. Decisions that affect the specification or task breakdown have been
resolved in this design.
