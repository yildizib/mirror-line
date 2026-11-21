# Tasks

- [x] Move the Flutter package to `apps/mobile` and update CI/release paths.
- [x] Move mobile models, DAOs, facades, UI services, and screens into feature-owned layers.
- [x] Rename connection orchestration to `SyncFacade` and isolate legacy LAN transport.
- [x] Extract decrypted-message dispatch into `MessageRouter`.
- [x] Remove remaining UI/UI-service imports of base or native services and enforce the rule in architecture tests.
- [x] Split Android native code into bridge, telephony, notifications, lifecycle, and runtime packages without changing channel contracts.
- [x] Add the Spring Boot/PostgreSQL/Flyway/push-gateway skeleton.
- [x] Add Docker Compose, Caddy, private database networking, healthchecks, and secret mounts.
- [x] Remove direct-main version commits from release automation.
- [x] Run all mobile, server build, container, infrastructure, OpenSpec, and graph verification gates.
- [ ] Complete the documented two-device Android smoke test.
