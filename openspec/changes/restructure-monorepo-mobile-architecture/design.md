# Design

## Repository boundaries

Flutter lives in `apps/mobile`, the Spring Boot service in `apps/server`,
language-neutral contracts in `packages/contracts`, and VPS runtime files in
`infra/vps`. Root-level documentation, OpenSpec, tools, and knowledge-graph
artifacts remain repository concerns.

## Mobile dependency direction

Each feature owns its `domain`, `base`, `facade`, `ui_service`, and `ui`
elements as needed. Domain code is infrastructure-free. Base code implements
persistence, platform, and transport details. Facades orchestrate base code.
UI services expose state/actions to widgets, and UI code must not import base
services, sockets, listeners, DAOs, or MethodChannels.

The connection feature becomes `sync`. `SyncFacade` owns lifecycle and sync
orchestration, `MessageRouter` dispatches decrypted frames to feature facade
contracts, and `LegacyLanTransportAdapter` names the current socket transport.
Existing protocol, encryption, retry, queue, and pairing behavior remains
compatible.

## Server and deployment skeleton

The server is one Gradle project with package-level modular-monolith
boundaries. Only Actuator health endpoints are public. All other requests are
denied until a later product API change defines them. Development uses a no-op
push gateway; the production profile initializes Firebase through Application
Default Credentials and sends only a `signal=sync` data hint.

Caddy is the only public container. The application and PostgreSQL use private
Compose networks, secrets are mounted or supplied through the environment, and
database state uses a named volume.

## Release safety

Flutter CI runs from `apps/mobile`; server and Compose validation receive their
own jobs. Release automation verifies the version already merged through a
release PR and never commits directly to `main`.
