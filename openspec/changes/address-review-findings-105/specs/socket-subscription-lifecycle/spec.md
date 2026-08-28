## Requirements

### Requirement: Subscription ownership
The socket manager MUST retain ownership of the active stream subscription.

#### Scenario: Socket is replaced
- **WHEN** a replacement socket becomes active
- **THEN** the prior subscription is cancelled and callbacks from the prior
  socket cannot change current connection state.

### Requirement: Teardown
The socket manager MUST cancel the active subscription during disconnect and
dispose.

#### Scenario: Manager is disposed
- **WHEN** the manager is disposed
- **THEN** the active subscription is cancelled and no later callback reaches
  application handlers.

