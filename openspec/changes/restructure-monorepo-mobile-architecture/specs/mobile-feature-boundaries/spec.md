# Mobile feature boundaries

## ADDED Requirements

### Requirement: UI depends on UI services

UI and UI-service code MUST NOT import DAO, socket, listener, MethodChannel, or
other concrete base implementations. UI services MUST orchestrate feature
facades, and feature facades MAY depend on base contracts and implementations.

#### Scenario: Architecture tests inspect imports

- **WHEN** a UI or UI-service Dart file imports a forbidden base/native path
- **THEN** the architecture test fails and reports the violating file

### Requirement: Legacy LAN is a replaceable transport

The current direct LAN/VPN implementation MUST be owned by the sync feature and
exposed as `LegacyLanTransportAdapter`. Its wire payload, encryption,
pairing, reconnect, and offline-queue behavior MUST remain compatible.

#### Scenario: Existing peers reconnect after migration

- **WHEN** two previously paired devices run the reorganized application
- **THEN** they reconnect and exchange existing message types without re-pairing
