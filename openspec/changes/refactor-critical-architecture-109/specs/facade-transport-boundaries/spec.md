# Facade transport boundaries

## Requirements

- Facades MUST depend on transport and routing ports rather than concrete UI services.
- Socket payload shape, queue/retry semantics, JSON persistence and database schema MUST remain compatible.
- Connection and pairing flows MUST preserve current success and failure behavior.
