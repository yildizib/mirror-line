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

### Requirement: QR bootstrap transport isolation

The system SHALL permit a QR-authorized pairing transaction before a remote
paired identity exists without treating it as authenticated normal peer
transport. An already paired connection with incomplete identity material
SHALL fail closed.

#### Scenario: Unpaired device receives a QR pairing request

- **WHEN** an unpaired listener receives a request encrypted with its active QR
  pairing secret
- **THEN** it SHALL keep the socket open long enough to validate and surface the
  pairing request instead of rejecting it for a missing remote public key

#### Scenario: Pairing bootstrap socket becomes connected

- **WHEN** a QR bootstrap socket is accepted
- **THEN** it SHALL NOT flush the application queue, mark normal peer transport
  authenticated, or enable normal reconnect side effects

#### Scenario: Paired connection lacks required identity

- **WHEN** transport is attempted for a completed remote peer but required
  local or remote identity material is missing
- **THEN** it SHALL fail closed and SHALL NOT downgrade to pairing mode

### Requirement: Deterministic pairing transaction

The system SHALL initialize pairing state before sending each request or
response, SHALL validate every pairing write result, and SHALL use the pending
transaction's expected remote identity for acknowledgement checks.

#### Scenario: Pairing response arrives immediately

- **WHEN** `pairing_accept` or `pairing_ack` arrives before the sender's write
  future completes
- **THEN** the response SHALL complete the active transaction instead of being
  discarded because its completion state was not initialized

#### Scenario: Pairing write fails

- **WHEN** a pairing request, accept, acknowledgement, or rejection cannot be
  written to the socket
- **THEN** the transaction SHALL enter a terminal failure state and SHALL NOT
  report delivery or pairing completion

#### Scenario: Valid acknowledgement reaches the scanned device

- **WHEN** the acknowledgement transaction ID and scanner identity match the
  pending incoming request
- **THEN** the scanned device SHALL accept it and may commit its peer record

### Requirement: Safe pairing endpoint selection

The system SHALL reject QR and pairing endpoints that are empty, invalid,
loopback, or owned by the receiving device, and SHALL NOT persist an
unvalidated claimed endpoint as a remote peer address.

#### Scenario: Distinct QR identity contains scanner local endpoint

- **WHEN** a QR payload has a distinct identity but its endpoint matches one of
  the scanner's local addresses
- **THEN** the scanner SHALL reject pairing before opening a socket

#### Scenario: Pairing message claims receiver address

- **WHEN** a request or accept claims an IP address owned by the device
  processing the message
- **THEN** the address SHALL NOT be persisted as the remote endpoint and the
  system SHALL expose an invalid-endpoint diagnostic

#### Scenario: Valid remote endpoint is supplied

- **WHEN** a pairing endpoint is valid, non-loopback, and not locally owned
- **THEN** the system SHALL use it subject to existing identity and transaction
  validation

### Requirement: Current local identity in QR pairing

The system SHALL use the displaying device's own ID, name, public key, and
current local endpoint when generating QR and pairing response identity data.
It SHALL NOT combine a remote peer record with local key material.

#### Scenario: QR is displayed after previous pairing

- **WHEN** the device displays a new QR while a remote peer record exists
- **THEN** the QR SHALL contain local device identity and SHALL NOT use the
  previous remote device ID or name as local identity

#### Scenario: QR identity is not ready

- **WHEN** the local public key, self identity, or usable endpoint is not ready
- **THEN** the UI SHALL NOT present a scannable QR containing placeholder or
  stale identity data

### Requirement: Replacement socket callback isolation

The system SHALL associate socket completion and error callbacks with the
socket instance that created them.

#### Scenario: Old socket closes after replacement

- **WHEN** a previous socket emits completion or error after a replacement
  socket becomes current
- **THEN** the stale callback SHALL NOT close, reset, or mark the replacement
  socket disconnected
