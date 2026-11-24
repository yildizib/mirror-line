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
header SHALL bind protocol, envelope, sender/recipient user and device IDs,
both signing/agreement key versions, message type, timestamps, expiry, nonce,
and ciphertext binding.

#### Scenario: Signed routing metadata is altered
- **WHEN** any signed sender, recipient, key-version, timestamp, or ciphertext
  binding field is changed after signing
- **THEN** the recipient SHALL reject the envelope before plaintext dispatch

### Requirement: Replay records are durable and bounded by policy

Recipients SHALL reject duplicate envelope IDs, accepted-header hashes,
unsupported versions, expired messages, invalid stream sequence, and freshness
violations before application dispatch. Accepted replay records SHALL persist
for eight days.

#### Scenario: An accepted envelope is redelivered
- **WHEN** an envelope already recorded as accepted is delivered again within
  eight days
- **THEN** the recipient SHALL not dispatch it a second time
- **AND** SHALL return the idempotent replay outcome

### Requirement: Mailbox and local history have explicit retention

The server SHALL retain accepted opaque mailbox envelopes for no more than seven
days. Devices SHALL offer local history periods of 7, 30, 90, and 180 days and
SHALL default to 30 days.

#### Scenario: A mailbox envelope reaches its retention limit
- **WHEN** the server retention job runs after seven days
- **THEN** it SHALL delete the envelope and content-bearing mailbox metadata
- **AND** SHALL not extend retention because delivery was not acknowledged
