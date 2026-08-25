## Purpose

Protect sensitive MirrorLine data stored on the device while preserving the
existing user experience and allowing existing installations to migrate safely.

## ADDED Requirements

### Requirement: Sensitive data at rest

The system SHALL store sensitive call, SMS, notification, and offline queue
content in encrypted form when persisted locally.

#### Scenario: Sensitive SMS fields are protected
- **WHEN** an SMS is persisted to the local database
- **THEN** the message body, address, and contact name SHALL NOT be stored as
  readable plaintext

#### Scenario: Sensitive call fields are protected
- **WHEN** a call event is persisted to the local database
- **THEN** the phone number and contact name SHALL NOT be stored as readable
  plaintext

#### Scenario: Sensitive notification fields are protected
- **WHEN** a mirrored notification is persisted to the local database
- **THEN** its application name, title, and text SHALL NOT be stored as
  readable plaintext

### Requirement: Local encryption key isolation

The system SHALL use a local encryption key that is separate from the peer
network encryption key, and the local encryption key SHALL NOT be persisted in
the SQLite database.

#### Scenario: Local key is created on first use
- **WHEN** the application needs to encrypt local data and no local key exists
- **THEN** the system SHALL generate a cryptographically secure local key and
  store it in Android Keystore-backed secure storage

#### Scenario: Network key is not stored as readable database data
- **WHEN** a peer record is persisted or updated
- **THEN** the peer network encryption key SHALL NOT be stored as readable
  plaintext in SQLite

### Requirement: Transparent UI decryption

The system SHALL decrypt protected local fields before they are exposed through
application models used by facades, providers, or UI components.

#### Scenario: Existing UI displays decrypted content
- **WHEN** a stored SMS, call, or notification is loaded successfully
- **THEN** the UI SHALL display its original human-readable values without
  exposing ciphertext

#### Scenario: Decryption failure is handled safely
- **WHEN** a protected field cannot be decrypted
- **THEN** the system SHALL not display the ciphertext as user content and SHALL
  expose a controlled unavailable-data state

### Requirement: Existing data migration

The system SHALL migrate existing plaintext records to the protected storage
format without losing readable user data when the required secure keys are
available.

#### Scenario: Existing installation is upgraded
- **WHEN** an existing database is opened after the security update
- **THEN** sensitive plaintext fields SHALL be encrypted and the upgraded
  records SHALL remain readable through the application

#### Scenario: Migration cannot access the required key
- **WHEN** migration cannot access the required secure storage key
- **THEN** the system SHALL not irreversibly delete the only recoverable copy
  of the affected data and SHALL report a controlled migration failure

#### Scenario: Migration is retried after interruption
- **WHEN** migration is interrupted before completion and the application is
  opened again
- **THEN** migration SHALL be safely resumable or repeatable without creating
  duplicate records

### Requirement: Encrypted offline queue

The system SHALL encrypt offline queue payloads before they are persisted and
SHALL decrypt them only when they are read for delivery.

#### Scenario: Queue payload is persisted while disconnected
- **WHEN** a message cannot be sent because the peer is unavailable
- **THEN** its queue payload SHALL be encrypted before being written to SQLite

#### Scenario: Queue payload is prepared for delivery
- **WHEN** connectivity returns and a queued message is selected for sending
- **THEN** the system SHALL decrypt the local queue payload and re-encrypt the
  message for network delivery
