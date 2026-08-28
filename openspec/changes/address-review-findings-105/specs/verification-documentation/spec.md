## ADDED Requirements

### Requirement: Accurate product documentation
The product documentation MUST describe schema version 7, the
`offline_queue.dedupe_key` column, and the distinction between stored peers
and the single active runtime peer.

#### Scenario: Documentation is reviewed
- **WHEN** the Turkish and English sections are compared with the code
- **THEN** schema and peer-runtime claims are consistent in both sections.

### Requirement: Explicit verification scope
CI and project documentation MUST distinguish automated checks from manual
two-device Android QA.

#### Scenario: Acceptance status is reported
- **WHEN** an acceptance item is marked complete
- **THEN** the evidence identifies whether it came from CI, an automated test,
  or a manual device run.
