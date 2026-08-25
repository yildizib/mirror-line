## Purpose

Ensures QR pairing remains an isolated transaction and that automatic network
discovery never treats an unpaired or local identity as a remote peer.

## ADDED Requirements

### Requirement: Pairing runtime state isolation

The system SHALL keep the temporary QR pairing connection independent from the
normal post-pairing connection and discovery lifecycle until pairing completes.

#### Scenario: QR request reaches the scanned device

- **WHEN** a scanner connects to a valid QR endpoint and sends a pairing request
- **THEN** the scanned device SHALL receive and process the request without a
  normal reconnect attempt replacing or closing the pairing connection

#### Scenario: Pairing request is pending

- **WHEN** either device is waiting for pairing acceptance or acknowledgement
- **THEN** normal peer reconnect and fallback discovery SHALL remain inactive

### Requirement: Valid discovery gating

The system SHALL only schedule automatic peer reconnect or fallback subnet
discovery when a completed remote peer exists and its endpoint has a valid
non-zero port and non-local address.

#### Scenario: Device is unpaired

- **WHEN** the active peer record has no completed remote identity
- **THEN** the system SHALL not schedule reconnects, advertise a remote peer, or
  scan a subnet using port `0`

#### Scenario: Stored endpoint is invalid

- **WHEN** the stored peer endpoint is empty, unknown, zero-port, or resolves to
  the local device identity
- **THEN** the system SHALL skip the attempt and expose a clear diagnostic state

### Requirement: Stale attempt cancellation

The system SHALL cancel or invalidate pending reconnect and discovery work when
pairing starts, pairing finishes, pairing is reset, or network state changes.

#### Scenario: Pairing starts during a scheduled reconnect

- **WHEN** a QR pairing transaction begins while a reconnect timer or scan is
  pending
- **THEN** the pending work SHALL be invalidated and SHALL not connect to the
  local device or interfere with the pairing socket

#### Scenario: Pairing is reset

- **WHEN** the user resets pairing or pairing times out
- **THEN** pending discovery work SHALL be cancelled and the device SHALL return
  to a clean unpaired state

### Requirement: Self-identity protection

The system SHALL reject a pairing request, QR payload, or persisted peer update
that identifies the local device as its own remote peer.

#### Scenario: QR contains the local device identity

- **WHEN** a scanned QR payload has the same peer identity as the local device
- **THEN** the system SHALL reject it without creating or replacing a peer row

#### Scenario: Incoming request claims the local identity

- **WHEN** an incoming pairing request claims the local device ID or public key
- **THEN** the system SHALL reject the request and SHALL not show a successful
  pairing state

### Requirement: Accurate peer presentation

The system SHALL expose only the completed remote peer as the paired device in
Settings and connection status.

#### Scenario: Device has only a self setup record

- **WHEN** a role has been selected but no remote pairing has completed
- **THEN** Settings SHALL show the device as unpaired rather than showing the
  local setup record as a remote peer

#### Scenario: Pairing completes on both devices

- **WHEN** the final pairing acknowledgement is verified
- **THEN** each device SHALL persist and present the other device's identity,
  address, role, and public key

### Requirement: Observable pairing diagnostics

The system SHALL log or expose enough non-secret diagnostic information to
distinguish QR parsing, TCP connection, pairing request delivery, acceptance,
acknowledgement timeout, and invalid self-peer rejection.

#### Scenario: Pairing fails after TCP connection

- **WHEN** TCP and initial authentication succeed but the pairing transaction
  does not complete
- **THEN** diagnostics SHALL identify the failed pairing stage without logging
  encryption keys or sensitive payload contents
