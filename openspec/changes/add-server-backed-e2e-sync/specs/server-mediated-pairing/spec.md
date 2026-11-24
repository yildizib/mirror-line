## ADDED Requirements

### Requirement: Pairing is coordinated by the server

The server SHALL create and coordinate pairing transactions. A transaction
shall have the states `created`, `redeemed`, `proofs_verified`,
`comparison_confirmed`, `completed`, `expired`, `cancelled`, `rejected`, and
`failed`. Only the first four are non-terminal.

The version-one endpoint contract SHALL be `POST /v1/pairings`,
`POST /v1/pairings/{pairingId}/redeem`, `GET /v1/pairings/{pairingId}`,
`POST /v1/pairings/{pairingId}/proofs`,
`POST /v1/pairings/{pairingId}/comparison-confirmations`, and
`DELETE /v1/pairings/{pairingId}`. State-changing requests SHALL support an
idempotency key and SHALL NOT reopen an expired or terminal transaction.

#### Scenario: A Source redeems a valid Main code
- **WHEN** an eligible Source redeems an active code
- **THEN** the server SHALL transition the transaction from `created` to
  `redeemed`
- **AND** SHALL make the transaction available to both authenticated devices

### Requirement: Pairing codes are short-lived and one-use

A pairing code SHALL be valid for five minutes and SHALL be consumed by its
first successful redemption. It SHALL NOT be reusable after expiry, redemption,
cancellation, or failure.

#### Scenario: A second Source presents a redeemed code
- **WHEN** a second redemption is attempted for a consumed code
- **THEN** the server SHALL reject it with `PAIRING_CODE_USED`
- **AND** SHALL not reveal the first Source's details

### Requirement: Both devices prove and compare the same transaction

Main and Source SHALL submit Ed25519 proofs over the server transaction ID,
fresh server challenge, canonical identities, roles, public-key versions, and
protocol version. Both SHALL explicitly confirm the same human-comparable value
derived from that verified transcript before membership is committed.

#### Scenario: The displayed comparison values differ
- **WHEN** either device reports a comparison mismatch
- **THEN** the server SHALL transition the transaction to `rejected`
- **AND** SHALL not create a pairing or device membership record

### Requirement: Pairing enforces membership limits atomically

Each user SHALL have exactly zero or one Main and no more than five Sources.
The server SHALL check and commit these limits atomically at completion.

#### Scenario: The fifth Source completes while another completion races
- **WHEN** a transaction would exceed five Sources at commit time
- **THEN** the server SHALL complete at most the transaction that obtained the
  final slot
- **AND** SHALL reject every other contender with `DEVICE_LIMIT_REACHED`
