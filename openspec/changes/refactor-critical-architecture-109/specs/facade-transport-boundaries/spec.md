# Facade transport boundaries

## ADDED Requirements

### Requirement: Facades use transport ports
Facades MUST depend on transport and routing ports rather than concrete UI services. Socket payload shape, queue/retry semantics, JSON persistence, and database schema MUST remain compatible. Connection and pairing flows MUST preserve current success and failure behavior.

#### Scenario: Existing message is routed through a port
- **WHEN** a facade sends or receives a protocol message
- **THEN** the wire payload and queue/retry behavior remain unchanged

#### Scenario: Existing message is routed through a port

- **WHEN** a facade sends or receives a protocol message
- **THEN** the wire payload and queue/retry behavior remain unchanged
