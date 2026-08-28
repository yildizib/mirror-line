## Requirements

### Requirement: Startup migration
The application MUST invoke the resumable local-storage migration before
normal production database use when migration is incomplete.

#### Scenario: Existing installation starts
- **WHEN** the application starts with an incomplete migration
- **THEN** the startup path runs the coordinator against the production
  database and only proceeds after the migration succeeds or safely reports a
  retryable failure.

### Requirement: Interrupted migration
The migration MUST resume from its durable checkpoint after interruption.

#### Scenario: Startup retries after interruption
- **WHEN** a prior migration stopped after a batch
- **THEN** the next startup resumes without corrupting or duplicating records.

