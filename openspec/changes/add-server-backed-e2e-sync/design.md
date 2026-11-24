## Context

The target product replaces direct LAN/VPN delivery with a server-mediated
encrypted mailbox. A device is registered to a server-issued UUIDv4 `userId`
and UUIDv4 `deviceId`; `(userId, deviceId)` is the canonical device identity.
The server routes opaque ciphertext but does not possess E2E private keys or
plaintext.

## Architecture

```text
Source device -- HTTPS/WebSocket --> authenticated relay <-- HTTPS/WebSocket -- Main device
     | encrypt + sign                                                         | verify + decrypt
     +--------------------------- encrypted envelope -------------------------+
```

All pairing coordination, device membership, relay delivery, key metadata,
and security audit traffic passes through the server. Pairing and normal
operation have no LAN, VPN, broadcast, discovery, IP address, or direct-socket
requirement.

The device architecture remains `base -> facade -> ui_service -> ui` in the
mobile app. Relay or socket clients remain base services; only facades expose
their product operations to UI services.

## Cryptographic contract

Each device has local-only Ed25519 signing and X25519 key-agreement private
keys. The two public keys rotate together under one monotonically increasing
`keyVersion`; they are not independently versioned. Public keys and their
shared version are registered with the server. Private keys MUST NOT be
uploaded, backed up by the server, or included in audit events.

For an envelope, the sender obtains the recipient's registered X25519 public
key at `recipientKeyVersion`, derives an envelope key with X25519 and
HKDF-SHA256, then encrypts the plaintext with AES-256-GCM. HKDF info is
envelope-specific and includes direction (sender/recipient user and device
IDs), `senderKeyVersion`, `recipientKeyVersion`, and `messageId`. The structured
signed fields are canonicalized using RFC 8785 JSON Canonicalization Scheme
before the Ed25519 signature is created or verified. The exact KDF salt and
wire byte encoding are T2 interoperability fixtures, not implementation-defined
values.

The signed header contains at least:

- `protocolVersion`, `messageId`, `messageType`, and `createdAt`;
- sender `userId`, `deviceId`, and `senderKeyVersion`;
- recipient `userId`, `deviceId`, and `recipientKeyVersion`;
- `nonce` and `ciphertext`; and
- `signature` over the canonical header excluding `signature` itself.

The canonical signed representation includes the ciphertext directly. It has no
client-signed `expiresAt` and needs no separate ciphertext-digest field. The
server assigns immutable `acceptedAt` after successful admission; retention is
authoritative from `acceptedAt + 7 days`.

The sender and recipient user IDs MUST be equal for this product. A server
MUST reject an envelope that addresses an unregistered, revoked, incorrectly
versioned, or cross-account device. A recipient MUST verify canonical form,
schema, identities, supported versions, signature, expiry, and AES-GCM
authentication before dispatching plaintext.

## Replay and retention

`messageId` is unique within its sender device identity and the receiver
persists sender-scoped replay records for eight days. A replay record contains a
message ID plus a persisted digest/tombstone of the accepted envelope. A
duplicate sender/message ID, a conflicting digest for that ID, unsupported
versions, or failed signature/AES-GCM verification is rejected before
application dispatch. `createdAt` is signed metadata but is neither a
uniqueness key nor a strict ordering requirement: a legitimate out-of-order or
offline envelope MUST NOT be rejected solely because of its creation time.

The server stores accepted opaque mailbox envelopes until `acceptedAt + 7 days`,
then deletes them and their content-bearing metadata; it exposes no plaintext
search. Delivery acknowledgement is idempotent and may safely be repeated.
Devices retain user-visible local history for one of 7, 30, 90, or 180 days;
the default is 30 days. Local-history deletion does not rewrite audit history or
extend mailbox retention.

## Time semantics

PostgreSQL `TIMESTAMPTZ` values and mobile epoch-millisecond values store UTC
instants. APIs emit ISO-8601 timestamps with a `Z` suffix, and domain values
normalize to UTC; only the UI converts instants to device-local time. Retention
uses a half-open interval `[created, expiry)`, so a record is expired exactly
at its configured expiry instant.

## Pairing

Pairing is a server transaction. A Main opens a one-use pairing code valid for
five minutes. A Source redeems it through the server, both devices submit
Ed25519 proofs over the transaction transcript, and both explicitly confirm a
human-comparable verification value derived from the registered public keys and
fresh server transaction data. The server commits membership only after both
proofs and confirmations pass. It enforces one Main and at most five Sources.

The state machine is `created -> redeemed -> proofs_verified ->
comparison_confirmed -> completed`, with terminal `expired`, `cancelled`,
`rejected`, and `failed` states. A code is consumed exactly once even when the
transaction later fails. Neither QR nor short code contains a private key,
relay address, IP address, port, shared AES key, or a direct-connect secret.

The version-one pairing endpoint contract is `POST /v1/pairings` to create a
Main-owned transaction, `POST /v1/pairings/{pairingId}/redeem` for a Source to
consume its code, `GET /v1/pairings/{pairingId}` for either participant's
redacted state, `POST /v1/pairings/{pairingId}/proofs` for signed proofs,
`POST /v1/pairings/{pairingId}/comparison-confirmations` for each explicit
comparison result, and `DELETE /v1/pairings/{pairingId}` to cancel before
completion. State-changing calls use request idempotency keys; an expired or
terminal transaction never reopens.

An authenticated Main may idempotently revoke a managed Source; self-revocation
invalidates its own session, so a lost-response retry terminates safely at
session invalidation rather than replaying a successful revoke response.

## Key lifecycle

Every device schedules key rotation every 90 days and supports manual and
emergency rotation. A rotation advances the single shared `keyVersion` for its
Ed25519 and X25519 public keys together. The rotating device provides a dual
old/new Ed25519 proof so peers can authenticate continuity. It collects required
peer acknowledgements, activates the new version after all acks or no later
than 24 hours, and preserves a 14-day old/new verification overlap. Emergency
rotation may revoke compromised old material immediately; affected peers must
re-establish trust according to the recovery contract.

## Sessions and audit

A successful authenticated login creates a device-bound session. A session is
active until explicit sign-out, password/security invalidation, device
revocation, expiry, or administrative safety action. Last-login means the most
recent successful authenticated session creation for that user, with timestamp,
device label/ID, and coarse network context; failed attempts do not replace it.

The server appends immutable security events for account access, session
creation/end/revocation, device registration/revocation, pairing states, key
rotation states, and mailbox-policy security rejections. Audit events contain
only identifiers and redacted operational context: no password, access token,
private key, pairing code, plaintext, ciphertext, message content, or raw IP
address. They are retained for one year and then deleted or irreversibly
anonymized by the retention job.

## API and compatibility

All product endpoints are versioned under `/v1`. API groups are authentication
and sessions, identity and devices, pairing, key lifecycle, mailbox sync,
security audit, and internal push wake-up. Responses use a stable JSON error
shape with a machine-readable `code`; clients branch on codes, never text.
Push contains only an opaque sync-required wake signal and no E2E content.

## Persistence boundaries

Server persistence uses Flyway migrations and `JdbcTemplate` with explicit SQL.
Service/facade methods define transaction boundaries, and PostgreSQL constraints
enforce identity, key-version, mailbox, quota, and append-only audit invariants.
JPA is intentionally not used: mailbox admission, audit immutability, key
lifecycle, and role/quota transitions are SQL- and concurrency-heavy rules that
must remain explicit and reviewable.

## Migration and rollout

T2-T14 build the new path behind explicit capability/version checks. T15
removes LAN/VPN transport only after parity and migration evidence. T16 adds
operations and retention jobs. T17 requires test, cross-network two-device,
security, and documentation acceptance evidence before release.

## Risks and open questions

- The exact protocol serialization and test vectors must be jointly frozen in
  T2 to prevent platform-specific canonicalization or KDF drift.
- Key acknowledgement handling during a device that is offline for over 24
  hours needs recovery UX specified with the mobile implementation; it may not
  cause a downgrade to an unverified key.
- Account credential policy and token lifetimes are intentionally deferred to
  the identity implementation, but must preserve the stated session semantics.
