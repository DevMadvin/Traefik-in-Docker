# Traefik

Production-ready [Traefik](https://traefik.io) v3 on Docker Compose. Point a Cloudflare domain at your server, edit `.env`, and put any other Compose stack on the same network.

Certificates are issued with the Let's Encrypt **DNS-01** challenge (Cloudflare), so you get a wildcard for `*.your.domain` without opening port 80 to the CA.

## What you get

- Traefik v3, pinned image, HTTP → HTTPS redirect
- Wildcard TLS via Cloudflare DNS
- Dashboard at `https://traefik.<your-domain>` with basic auth, IP allowlist, and rate limits
- Docker provider (`exposedByDefault=false`) plus a watched `config/` directory for non-Docker backends
- Named Docker network that other projects can join
- JSON logs with rotation (optional syslog overlay)
- Hardened container: dropped capabilities, read-only root, no new privileges

## Requirements

- Docker Engine with Compose v2
- A domain whose DNS is on Cloudflare
- Host ports **80** and **443** (or change `HTTP_PORT` / `HTTPS_PORT`)

## Quick start

```bash
cp .env.example .env
# edit .env — token, email, domain, dashboard password, your admin IP
./init.sh
docker compose up -d
```

Open `https://traefik.<PRIMARY_DOMAIN>` and sign in with `DASHBOARD_USER` / `DASHBOARD_PASSWORD`.

`./init.sh` writes a hashed `traefik/auth/users` file and creates the data directories. Re-run it after you change the dashboard password. `./init.sh --up` also starts the stack.

If you already had `traefik/acme.json` from an older layout, `init.sh` moves it to `traefik/letsencrypt/acme.json`.

## Configure with `.env`

| Variable | Purpose |
| --- | --- |
| `CF_DNS_API_TOKEN` | Cloudflare API token (`Zone:Read`, `DNS:Edit`) |
| `ACME_EMAIL` | Let's Encrypt account / expiry mail |
| `ACME_CA_SERVER` | Optional. Staging URL while you test |
| `PRIMARY_DOMAIN` | Apex + wildcard covered by the first certificate |
| `DASHBOARD_USER` / `DASHBOARD_PASSWORD` | Dashboard login (hashed by `init.sh`) |
| `DASHBOARD_ALLOWED_IPS` | CIDRs allowed to reach the dashboard |
| `DOCKER_NETWORK_NAME` | Network name other stacks should join (`web` by default) |
| `HTTP_PORT` / `HTTPS_PORT` | Host ports |
| `TRAEFIK_LOG_LEVEL` / `TRAEFIK_LOG_FORMAT` | Container logs |
| `TRAEFIK_ACCESSLOG` | Set `true` to log every request |

Compose fails fast if the required variables are missing.

### Let's Encrypt staging

Uncomment in `.env` before the first certificate request if you are still experimenting:

```env
ACME_CA_SERVER=https://acme-staging-v02.api.letsencrypt.org/directory
```

Switch back to production, remove `traefik/letsencrypt/acme.json`, and recreate the container so Traefik can issue trusted certs.

## Route a Docker app

Create the Traefik stack first so the network exists. In the other project:

```yaml
services:
  myapp:
    image: myorg/myapp
    networks:
      - web
    labels:
      - traefik.enable=true
      - traefik.http.routers.myapp.rule=Host(`app.example.com`)
      - traefik.http.routers.myapp.entrypoints=websecure
      - traefik.http.routers.myapp.tls=true
      - traefik.http.routers.myapp.tls.certresolver=letsencrypt
      - traefik.http.routers.myapp.middlewares=security-headers@docker
      - traefik.http.services.myapp.loadbalancer.server.port=8080

networks:
  web:
    external: true
    name: web
```

A full whoami example lives in [`config_examples/whoami.docker-compose.yml`](config_examples/whoami.docker-compose.yml).

## Non-Docker services

Copy [`config_examples/external-service.yml`](config_examples/external-service.yml) into `config/` and change the host and upstream URL. Traefik watches that directory and reloads without a container restart.

## Extra domains

The dashboard router requests `PRIMARY_DOMAIN` and `*.PRIMARY_DOMAIN`. For more wildcards, add labels on the `traefik` service in `docker-compose.yml`:

```yaml
- "traefik.http.routers.traefik-dashboard.tls.domains[1].main=${EXTRA_DOMAIN_1}"
- "traefik.http.routers.traefik-dashboard.tls.domains[1].sans=*.${EXTRA_DOMAIN_1}"
```

Define `EXTRA_DOMAIN_1` in `.env`. Repeat with `[2]`, `[3]`, … as needed. Do not leave unused index entries empty — Traefik will reject them.

## Operations

| Task | Command |
| --- | --- |
| Change `.env` or compose and apply | `./reload.sh` |
| Only change files in `config/` | Save the file (watched) |
| Logs | `docker logs -f traefik` |
| Status | `docker compose ps` |

`reload.sh` re-hashes the dashboard user, validates Compose (and `config/*.yml` if PyYAML is installed), then recreates Traefik and waits until the official `traefik healthcheck --ping` reports healthy.

### Remote syslog

```bash
# in .env
LOG_SERVER_ADDRESS=udp://127.0.0.1:514

docker compose -f docker-compose.yml -f docker-compose.syslog.yml up -d
```

## Production notes

- **Dashboard DNS.** Keep `traefik.<domain>` DNS-only (grey cloud) in Cloudflare if you rely on `DASHBOARD_ALLOWED_IPS`. When the record is proxied, Traefik sees Cloudflare addresses, not yours.
- **Backup** `traefik/letsencrypt/acme.json`. Losing it and re-requesting can hit Let's Encrypt rate limits.
- **Docker socket** is mounted read-only. That is still a high-privilege control plane; only run this stack on hosts you administer.
- The ping endpoint listens inside the container on port 8080 and is **not** published.
- Other routers can reuse `security-headers@docker` and `dashboard-auth@docker` if you want the same middlewares.

## License

MIT — see [LICENSE](LICENSE).
