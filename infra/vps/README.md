# MirrorLine VPS stack

The production-shaped stack exposes only Caddy on ports 80/443. The Spring
server is reachable only from the edge network and PostgreSQL only from the
internal data network.

1. Copy `.env.example` to `.env` and replace every placeholder.
2. Put the Firebase service-account JSON at the configured secret path.
3. Validate with `docker compose config --quiet`.
4. Start with `docker compose up --build -d` only on the target VPS.

No deployment is performed by repository CI.
