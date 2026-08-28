## Requirements

### Requirement: UI service boundary
The Settings screen MUST use a UI-facing controller or facade for native
settings operations and MUST NOT call core telephony channels directly.

#### Scenario: User opens a native settings page
- **WHEN** a Settings action is tapped
- **THEN** the screen invokes the UI service boundary, which performs the
  native operation.

### Requirement: Selective rebuilds
Settings sections MUST subscribe only to the connection fields they render.

#### Scenario: Discovery log changes
- **WHEN** a discovery-log entry changes
- **THEN** unrelated Settings sections do not rebuild solely because of that
  log update.

