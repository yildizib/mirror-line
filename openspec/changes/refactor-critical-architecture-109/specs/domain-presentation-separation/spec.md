# Domain presentation separation

## ADDED Requirements

### Requirement: Domain models are presentation independent
CallEvent and SmsMessage MUST remain locale-independent data models. Localization and display/status formatting MUST be performed by presentation services or mappers. Peer MUST NOT depend on a concrete crypto manager; verification-code generation MUST be injectable.

#### Scenario: Domain data is locale independent
- **WHEN** a call or SMS is serialized or consumed by a facade
- **THEN** no localization lookup or UI label is required

#### Scenario: Domain data is locale independent

- **WHEN** a call or SMS is serialized or consumed by a facade
- **THEN** no localization lookup or UI label is required
