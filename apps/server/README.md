# MirrorLine Server

Kotlin/Spring Boot modular-monolith skeleton for the future server-backed
MirrorLine transport. This change exposes health probes only; account, device,
mailbox, and relay product APIs are intentionally absent.

## Local checks

```bash
./gradlew check
```

The application expects PostgreSQL. Production also requires
`MIRRORLINE_PUBLIC_DOMAIN` and Application Default Credentials for Firebase.
