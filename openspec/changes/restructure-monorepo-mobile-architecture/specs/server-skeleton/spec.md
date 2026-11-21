# Server skeleton

## ADDED Requirements

### Requirement: Server exposes operational health only

The initial server MUST expose Actuator health, liveness, and readiness probes
without exposing product account, device, mailbox, or relay APIs. Unknown
requests MUST be denied by default.

#### Scenario: Container readiness is checked

- **WHEN** the container runtime calls `/actuator/health/readiness`
- **THEN** the server reports readiness after PostgreSQL and Flyway are ready

### Requirement: Push signals contain no product content

The push gateway MUST send only an opaque wake/sync signal. Calls, SMS,
notifications, commands, and encrypted mailbox payloads MUST NOT be included.

#### Scenario: Production wake signal is built

- **WHEN** the push gateway requests device synchronization
- **THEN** the FCM data contains only the sync signal and targeting token

### Requirement: Database is not publicly exposed

The VPS Compose model MUST expose only Caddy ports 80 and 443. PostgreSQL MUST
remain on an internal network with persistent storage and a healthcheck.

#### Scenario: Compose model is rendered

- **WHEN** operators run `docker compose config`
- **THEN** PostgreSQL has no host port mapping and the server depends on its health
