## ADDED Requirements

### Requirement: Device private keys remain device-local

Each device SHALL generate and protect its Ed25519 and X25519 private keys
locally. The service SHALL store only public keys, public-key versions, and
non-secret lifecycle metadata.

#### Scenario: A device registers key material
- **WHEN** a device registers or rotates keys
- **THEN** the request SHALL contain only public keys and proofs
- **AND** the server SHALL reject a request that includes private-key material

### Requirement: Rotation has scheduled, manual, and emergency paths

Devices SHALL schedule rotation every 90 days and SHALL support manual and
emergency rotation. A rotation SHALL carry a dual old/new Ed25519 proof of
continuity, require peer acknowledgement, activate at all required
acknowledgements or within 24 hours, and retain a 14-day old/new verification
overlap.

#### Scenario: A peer is offline during normal rotation
- **WHEN** a scheduled rotation has not received every acknowledgement by 24
  hours
- **THEN** the server SHALL activate the new version according to the approved
  timeout policy
- **AND** SHALL keep the old version valid only within the 14-day overlap

#### Scenario: Emergency rotation is requested
- **WHEN** a device declares its prior key compromised
- **THEN** the server SHALL record an emergency lifecycle event and revoke or
  restrict the old version according to recovery policy
- **AND** SHALL not permit unsigned fallback to the new key
