## ADDED Requirements

### Requirement: Product APIs are grouped and versioned

The service SHALL expose product APIs under `/v1` in these groups:
authentication and sessions, identity and devices, pairing, key lifecycle,
mailbox sync, security audit, and internal push wake-up. Public clients SHALL
NOT use internal push administration endpoints.

Successful device-bound session creation and refresh responses SHALL include the
server-issued `userId` and `deviceId` associated with that session. A
device-enrollment grant response SHALL include its server-issued `userId`.
Clients SHALL NOT supply either response identity value, and the service SHALL
not derive it from a client-provided token claim.

#### Scenario: A mobile client requests a future API version
- **WHEN** the request targets an unsupported version
- **THEN** the service SHALL return `API_VERSION_UNSUPPORTED`
- **AND** SHALL not interpret it as `/v1`

### Requirement: Server persistence uses explicit relational boundaries

The server SHALL use Flyway migrations and `JdbcTemplate` explicit SQL for
product persistence. Service/facade methods SHALL define transaction boundaries,
and PostgreSQL constraints SHALL enforce identity, key-version, mailbox, quota,
and append-only audit invariants. The server SHALL NOT use JPA for these
SQL- and concurrency-heavy rules.

#### Scenario: Concurrent source pairing reaches quota
- **WHEN** concurrent pairing completions compete for the final Source slot
- **THEN** the PostgreSQL constraint and transaction boundary SHALL admit at
  most one completion
- **AND** the losing request SHALL receive `DEVICE_LIMIT_REACHED`

### Requirement: Error codes are stable and machine-readable

Errors SHALL return a stable `code`, safe message, request correlation ID, and
optional field details. The initial stable set SHALL include:

- `VALIDATION_FAILED`, `AUTH_INVALID_CREDENTIALS`, `AUTH_SESSION_EXPIRED`,
  `AUTH_FORBIDDEN`, `RATE_LIMITED`, `API_VERSION_UNSUPPORTED`, and
  `SERVICE_UNAVAILABLE`;
- `DEVICE_NOT_FOUND`, `DEVICE_REVOKED`, `DEVICE_ROLE_CONFLICT`, and
  `DEVICE_LIMIT_REACHED`;
- `PAIRING_NOT_FOUND`, `PAIRING_CODE_INVALID`, `PAIRING_CODE_EXPIRED`,
  `PAIRING_CODE_USED`, `PAIRING_STATE_INVALID`, `PAIRING_PROOF_INVALID`, and
  `PAIRING_COMPARISON_MISMATCH`;
- `KEY_VERSION_UNSUPPORTED`, `KEY_ROTATION_CONFLICT`, and `KEY_ACK_REQUIRED`;
- `ENVELOPE_INVALID`, `ENVELOPE_SIGNATURE_INVALID`, `ENVELOPE_EXPIRED`,
  `ENVELOPE_REPLAYED`, and `MAILBOX_CURSOR_INVALID`; and
- `AUDIT_EVENT_NOT_FOUND`.

#### Scenario: A retryable dependency fails
- **WHEN** the service cannot complete a request because a required dependency
  is temporarily unavailable
- **THEN** it SHALL return `SERVICE_UNAVAILABLE`
- **AND** SHALL not return an implementation-specific exception string

### Requirement: Push wake-up contains no product content

The internal push group SHALL send only a generic sync-required wake signal and
an opaque target reference. It SHALL NOT include calls, SMS, notifications,
commands, identities beyond routing needs, keys, or encrypted envelopes.

#### Scenario: A mailbox receives an envelope
- **WHEN** the service signals a recipient device to synchronize
- **THEN** the push payload SHALL contain no envelope plaintext or ciphertext
