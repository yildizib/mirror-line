## Purpose

Ensure that peer messages are confidential, cryptographically bound to their
metadata and session, authenticated by both devices, and processed within
bounded resource limits.

## ADDED Requirements

### Requirement: Authenticated message envelope

The system SHALL cryptographically authenticate message metadata including the
protocol version, message type, message ID, and timestamp together with the
encrypted payload.

#### Scenario: Valid message envelope is accepted
- **WHEN** a peer sends a message with unchanged authenticated metadata and a
  valid encrypted payload
- **THEN** the receiving device SHALL decrypt and process the message

#### Scenario: Message type is modified in transit
- **WHEN** the message type is changed without regenerating valid
  authenticated data
- **THEN** the receiving device SHALL reject the message

#### Scenario: Message timestamp is modified in transit
- **WHEN** the timestamp is changed without regenerating valid authenticated
  data
- **THEN** the receiving device SHALL reject the message

### Requirement: Mutual peer authentication

The system SHALL require both devices to prove possession of the expected
Ed25519 private identity key before treating a paired connection as
authenticated.

#### Scenario: Both peer identities are valid
- **WHEN** each device verifies the other device's challenge signature against
  the public key stored during pairing
- **THEN** the connection SHALL become authenticated and normal messages SHALL
  be allowed

#### Scenario: Server identity is not valid
- **WHEN** the connecting device cannot verify the server's identity signature
- **THEN** the connection SHALL be closed and normal messages SHALL NOT be
  processed

#### Scenario: Client identity is not valid
- **WHEN** the server cannot verify the client's identity signature
- **THEN** the connection SHALL be closed and normal messages SHALL NOT be
  processed

### Requirement: Session-bound message freshness

The system SHALL reject messages that belong to a previous session or that have
already been accepted in the current session.

#### Scenario: Previously accepted message ID is received again
- **WHEN** a message with an already accepted session and message ID is
  received
- **THEN** the system SHALL reject it without repeating its side effect

#### Scenario: Message is outside the accepted time window
- **WHEN** a message timestamp is older or newer than the configured freshness
  window
- **THEN** the system SHALL reject the message

#### Scenario: Valid messages share a timestamp
- **WHEN** two distinct valid messages are created within the same timestamp
  unit
- **THEN** both messages SHALL be eligible for processing when their IDs and
  sequence data are valid

### Requirement: Bounded transport frames

The system SHALL enforce maximum frame, JSON, and encrypted payload sizes
before allocating unbounded memory or processing a message.

#### Scenario: Frame exceeds the maximum size
- **WHEN** a peer sends a frame larger than the configured maximum
- **THEN** the system SHALL reject the frame and close or reset the offending
  connection

#### Scenario: Invalid or incomplete frame remains open
- **WHEN** a peer sends an incomplete frame that does not reach a valid boundary
  within the configured limit
- **THEN** the system SHALL release the connection resources instead of growing
  the receive buffer without a bound

### Requirement: Bounded offline queue

The system SHALL enforce maximum queue size, item size, retry count, and item
retention time.

#### Scenario: Queue reaches its item limit
- **WHEN** a new message is queued after the configured queue limit is reached
- **THEN** the system SHALL apply the defined overflow policy and SHALL NOT grow
  the queue without a bound

#### Scenario: Queue item reaches its retention limit
- **WHEN** a queued item exceeds its configured time-to-live
- **THEN** the system SHALL remove or mark the item failed according to the
  defined delivery policy
