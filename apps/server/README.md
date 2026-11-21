# MirrorLine Server

Kotlin/Spring Boot modular-monolith skeleton for the future server-backed
MirrorLine transport. This change exposes health probes only; account, device,
mailbox, and relay product APIs are intentionally absent.

## Local checks

```bash
./gradlew clean build
docker build --tag mirrorline-server:local .
test "$(docker image inspect mirrorline-server:local --format '{{.Config.User}}')" = "mirrorline"
docker run --rm --entrypoint /bin/sh mirrorline-server:local \
  -c 'test "$(id -u)" -ne 0 && test -r /app/app.jar'
```

The Gradle build runs formatting checks, compilation, unit tests, Spring context
tests, and the Testcontainers PostgreSQL/Flyway integration test. The container
checks build both Docker stages and verify that the runtime image can read the
application artifact without running as root.

The application expects PostgreSQL. Production also requires
`MIRRORLINE_PUBLIC_DOMAIN` and Application Default Credentials for Firebase.
