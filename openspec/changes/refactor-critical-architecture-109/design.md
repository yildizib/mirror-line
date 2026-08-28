# Design

The UI accesses only feature controller and gateway contracts. Platform channels, permissions, notification routing, and key-store implementations remain infrastructure adapters.

Domain models do not know about localization or presentation formatting. Localization, verification-code presentation, and status labels are provided by presentation services.

Facades depend on transport and message-routing ports. Socket managers and concrete cryptographic implementations are supplied by infrastructure. Wire payloads, queue/retry behavior, and persistence semantics remain unchanged.
