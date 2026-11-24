# MirrorLine VPS stack

The production-shaped stack exposes only Caddy on ports 80/443. The Spring
server is reachable only from the edge network and PostgreSQL only from the
internal data network.

1. Copy `.env.example` to `.env` and replace every placeholder. Set
   `MIRRORLINE_PAIRING_CODE_HMAC_KEY` to the unpadded base64url encoding of at
   least 32 cryptographically random bytes. It is a production secret used to
   derive retry-safe pairing transfer codes; do not commit it.
2. Put the Firebase service-account JSON at the configured secret path.
3. Validate with `docker compose config --quiet`.
4. Start with `docker compose up --build -d` only on the target VPS.

No deployment is performed by repository CI.
