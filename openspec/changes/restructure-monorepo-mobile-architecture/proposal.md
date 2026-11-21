# Restructure monorepo and mobile architecture

MirrorLine's Flutter package currently owns the repository root and mixes
feature models, persistence, LAN transport, UI services, and screens. This
change establishes explicit mobile/server boundaries and makes the current
LAN/VPN behavior a replaceable legacy transport without implementing the
future relay product API.

The Flutter application moves to `apps/mobile` and remains one APK supporting
Main and Source roles. A Kotlin/Spring Boot modular-monolith skeleton is added
at `apps/server`, with PostgreSQL/Flyway, health probes, deny-by-default
security, and a content-free push gateway. Docker Compose and Caddy define the
future VPS runtime while keeping PostgreSQL private.

## Non-goals

- Account, device registration, mailbox, retention, or relay endpoints.
- Changing the legacy LAN wire format, queue semantics, persistence schema, or
  pairing behavior.
- Deploying to a VPS or adding Firebase configuration to the mobile app.
