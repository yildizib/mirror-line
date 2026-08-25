## Purpose

Keeps temporary pairing listeners isolated from normal peer reconnect behavior
and ensures disconnected paired devices retry safely without busy loops.

## ADDED Requirements

### Requirement: Pairing listener isolation

The system SHALL keep a temporary pairing listener available for incoming QR
transactions and SHALL NOT use that listener as the normal outbound peer
connection.

#### Scenario: Unpaired device receives a network change

- **WHEN** an unpaired device receives a network-change event while its pairing
  listener is active
- **THEN** the device SHALL preserve the pairing listener and SHALL NOT start a
  normal peer reconnect or subnet scan

#### Scenario: Manual reconnect is requested before pairing completes

- **WHEN** a user requests reconnect while no completed remote peer identity
  exists
- **THEN** the request SHALL finish without dialing through the pairing
  listener and SHALL expose an unpaired or unavailable-peer diagnostic

### Requirement: Safe reconnect ownership

The system SHALL use a client-capable connection for outbound reconnects and
SHALL never replace or clobber a listener that is accepting pairing or peer
connections.

#### Scenario: Outbound reconnect follows a pairing listener

- **WHEN** a completed remote peer becomes available after a pairing listener
  was used
- **THEN** the outbound reconnect SHALL use a client connection and the
  listener SHALL be stopped or retained independently according to the active
  role

#### Scenario: Server-mode connection is selected for reconnect

- **WHEN** reconnect logic resolves a connection currently operating as a
  server
- **THEN** the reconnect SHALL be rejected or redirected to a separate client
  connection without closing the server unexpectedly

### Requirement: Bounded reconnect retry

The system SHALL apply a bounded positive retry delay after failed reconnects
and SHALL treat a failed connection result as a failed attempt.

#### Scenario: Reconnect attempts continue failing

- **WHEN** repeated reconnect attempts fail
- **THEN** the retry delay SHALL never become zero and SHALL remain at or below
  the configured maximum delay

#### Scenario: Connection callback reports failure

- **WHEN** the outbound connection callback completes without establishing a
  connection
- **THEN** the scheduler SHALL record the attempt as failed and SHALL apply its
  retry policy rather than marking the scheduler connected
