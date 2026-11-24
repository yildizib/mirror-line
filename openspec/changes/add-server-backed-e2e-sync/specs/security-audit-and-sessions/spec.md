## ADDED Requirements

### Requirement: Sessions and last-login have defined semantics

A successful authenticated login SHALL create a device-bound session. A session
shall end on explicit sign-out, expiration, user/security invalidation, or
device revocation. Last login SHALL identify the most recent successful session
creation and SHALL NOT be overwritten by a failed attempt.

#### Scenario: A failed login follows a valid login
- **WHEN** an authentication attempt fails after a successful session was made
- **THEN** the stored last-login timestamp and device reference SHALL remain
  unchanged

### Requirement: Security audit records are append-only and redacted

The service SHALL append security audit events for authentication, session,
device, pairing, key lifecycle, and relay-security decisions. Audit records
SHALL NOT contain passwords, tokens, private keys, pairing codes, plaintext,
ciphertext, message content, or raw IP addresses.

#### Scenario: A pairing proof fails
- **WHEN** the server rejects an invalid pairing proof
- **THEN** it SHALL append a redacted proof-rejection event with identifiers,
  reason code, and timestamp
- **AND** SHALL not store the proof value or pairing code

### Requirement: Security audits are retained for one year

Audit events SHALL remain append-only for one year and SHALL then be deleted or
irreversibly anonymized by the retention process.

#### Scenario: An audit event is older than one year
- **WHEN** the audit retention job processes an event beyond one year
- **THEN** it SHALL remove or irreversibly anonymize the event
- **AND** SHALL preserve no content or secret value through the retention path
