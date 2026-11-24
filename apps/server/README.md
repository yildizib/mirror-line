# MirrorLine Server

Kotlin/Spring Boot service for server-mediated MirrorLine account, device, and
pairing workflows. It exposes health probes, opaque-session account APIs,
device enrollment/revocation, and authenticated server-mediated pairing. Relay
mailbox delivery remains a separate capability.

## Local checks

```bash
./gradlew clean build --no-build-cache
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
`MIRRORLINE_PUBLIC_DOMAIN`, Application Default Credentials for Firebase, and
`MIRRORLINE_PAIRING_CODE_HMAC_KEY`: the unpadded base64url encoding of at least
32 cryptographically random bytes. This HMAC key is validated at startup and
must be supplied only through environment/secret management, never source or
logs.
