## Purpose

Ensure that pairing approval establishes the intended device identity and
public-key relationship instead of trusting unbound values received from the
network or QR payload.

## ADDED Requirements

### Requirement: Pairing identity binding

The system SHALL bind the approved peer ID, device identity, role, and Ed25519
public key to the same pairing transaction.

#### Scenario: Pairing identity data is consistent
- **WHEN** the QR data, pairing request, pairing accept, and verification data
  identify the same peer and public key
- **THEN** the system SHALL allow the pairing transaction to continue

#### Scenario: Pairing public key changes unexpectedly
- **WHEN** the public key in a pairing response differs from the key bound to
  the pairing transaction
- **THEN** the system SHALL reject the pairing and SHALL NOT persist the peer

#### Scenario: Pairing peer ID changes unexpectedly
- **WHEN** the peer ID in a pairing response differs from the ID bound to the
  pairing transaction
- **THEN** the system SHALL reject the pairing and SHALL NOT persist the peer

### Requirement: Verification code covers peer identity

The pairing verification value SHALL be derived from the shared pairing secret
and the expected peer identity, including the public-key identity.

#### Scenario: Verification values match
- **WHEN** both devices calculate the verification value from the same pairing
  secret and peer identity
- **THEN** the user SHALL be able to confirm that both devices see the same
  identity

#### Scenario: Public key is replaced
- **WHEN** the public key changes while the pairing secret and peer ID remain
  unchanged
- **THEN** the verification value SHALL no longer match

### Requirement: Pairing confirmation is atomic

The system SHALL persist a paired peer only after the pairing transaction has
completed its required mutual confirmation and acknowledgement.

#### Scenario: Pairing acknowledgement is received
- **WHEN** both sides have accepted the identity data and the final
  acknowledgement is received
- **THEN** both devices SHALL persist the paired peer using the verified
  identity data

#### Scenario: Pairing acknowledgement is lost
- **WHEN** the final acknowledgement is not received before the pairing timeout
- **THEN** the device SHALL not persist an incomplete paired state
