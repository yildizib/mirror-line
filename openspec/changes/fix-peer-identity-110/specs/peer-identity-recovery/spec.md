## ADDED Requirements

### Requirement: Local identity is distinct from remote identity

The system SHALL use a persisted local self ID for beacons and local
authentication metadata, and SHALL NOT substitute the remote paired peer ID.

#### Scenario: Local self ID is missing

- **WHEN** discovery starts without a stored self ID
- **THEN** the system SHALL generate and persist one before broadcasting
- **AND** SHALL continue to keep the remote peer ID separate

#### Scenario: Beacon uses the remote ID as local ID

- **WHEN** a local beacon would be emitted with the paired remote ID
- **THEN** the system SHALL reject that local identity configuration
- **AND** SHALL repair or stop broadcasting until a valid local ID exists

### Requirement: Peer display fields are safe to render

The system SHALL never display encrypted storage ciphertext as a device name.

#### Scenario: Persisted display value is malformed or double-encrypted

- **WHEN** the stored peer name cannot be decoded to a human-readable value
- **THEN** the system SHALL show a safe fallback label
- **AND** SHALL preserve secret material and provide diagnostics without
  logging it

### Requirement: Endpoint recovery is authenticated

The system SHALL update a paired endpoint only after the beacon or transport
has passed the existing expected-identity and authentication checks.

#### Scenario: Valid peer moves to a new address

- **WHEN** an authenticated peer is observed at a new validated address
- **THEN** the system SHALL persist the new endpoint
- **AND** SHALL stop or invalidate retries targeting the old endpoint

#### Scenario: Unauthenticated identity changes

- **WHEN** a beacon presents an unexpected peer ID or key
- **THEN** the system SHALL reject it and SHALL NOT overwrite the paired record
