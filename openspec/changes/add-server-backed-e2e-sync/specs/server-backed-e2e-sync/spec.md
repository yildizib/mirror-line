## ADDED Requirements

### Requirement: Server-mediated encrypted relay is the only target transport

The target product SHALL mediate pairing and relay synchronization through the
server and SHALL NOT require LAN, VPN, broadcast discovery, IP addresses, or
direct device sockets. The server SHALL route opaque encrypted envelopes and
SHALL NOT receive E2E private keys or plaintext.

#### Scenario: Devices are on independent networks
- **WHEN** an authenticated Main and Source are connected to the service from
  independent networks
- **THEN** they SHALL be able to pair and synchronize through the server
- **AND** neither device SHALL need the other's network address

### Requirement: Devices use canonical server-issued identities

The server SHALL generate UUIDv4 `userId` and UUIDv4 `deviceId` values. The
canonical device identity SHALL be the ordered pair `(userId, deviceId)`.

#### Scenario: A client attempts to select its own device ID
- **WHEN** a device registration request includes a client-chosen device ID
- **THEN** the server SHALL ignore or reject that value
- **AND** SHALL return only a server-generated UUIDv4 device ID on success

### Requirement: Envelopes are encrypted, canonicalized, and signed

Each relay envelope SHALL use X25519 with HKDF-SHA256 to derive an
envelope-specific key, AES-256-GCM to encrypt the payload, RFC 8785 canonical
JSON for signed structured fields, and Ed25519 for the signature. The signed
representation SHALL directly bind `protocolVersion`, `messageId`,
`messageType`, `createdAt`, sender/recipient user and device IDs,
`senderKeyVersion`, `recipientKeyVersion`, `nonce`, and `ciphertext`.
`signature` SHALL be the Ed25519 signature of that RFC 8785 canonical
representation. A device's Ed25519 and X25519 keys SHALL rotate together under
one key version. HKDF info SHALL include the sender/recipient identities and
key versions plus `messageId`.

#### Scenario: Signed routing metadata is altered
- **WHEN** any signed sender, recipient, key-version, timestamp, or ciphertext
  binding field is changed after signing
- **THEN** the recipient SHALL reject the envelope before plaintext dispatch

### Requirement: Replay records are durable and bounded by policy

Recipients SHALL reject duplicate sender-scoped `messageId` values, conflicting
persisted digest/tombstones for those IDs, unsupported versions, and failed
signature or AES-GCM verification before application dispatch. Accepted replay
records SHALL persist for eight days. `createdAt` SHALL be signed metadata but
SHALL NOT be used as a strict ordering or uniqueness requirement that rejects
legitimate out-of-order or offline delivery.

#### Scenario: An accepted message is redelivered
- **WHEN** a sender/device `messageId` already recorded as accepted is
  delivered again within eight days
- **THEN** the recipient SHALL not dispatch it a second time
- **AND** SHALL return the idempotent replay outcome

### Requirement: Mailbox and local history have explicit retention

The server SHALL assign `acceptedAt` to an accepted opaque mailbox envelope and
retain it only until `acceptedAt + 7 days`. Client-signed envelope data SHALL
NOT set or extend mailbox retention. Devices SHALL offer local history periods
of 7, 30, 90, and 180 days and SHALL default to 30 days.

#### Scenario: A mailbox envelope reaches its retention limit
- **WHEN** the server retention job runs after `acceptedAt + 7 days`
- **THEN** it SHALL delete the envelope and content-bearing mailbox metadata
- **AND** SHALL not extend retention because delivery was not acknowledged
