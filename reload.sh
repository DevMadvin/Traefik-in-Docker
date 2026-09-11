#!/usr/bin/env bash
# Validate config and recreate Traefik after .env or compose changes.
# Dynamic files in ./config are watched live — no reload needed for those.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

COMPOSE_FILE="$ROOT/docker-compose.yml"
CONTAINER="traefik"

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$ROOT/.env" ]] || die ".env is missing. Copy .env.example to .env, then run ./init.sh"

log "Preparing dashboard auth and directories..."
"$ROOT/init.sh" --prepare-only

log "Validating docker-compose.yml..."
docker compose --env-file "$ROOT/.env" -f "$COMPOSE_FILE" config --quiet
log "  docker-compose.yml is valid"

if command -v python3 >/dev/null 2>&1; then
  shopt -s nullglob
  yaml_files=("$ROOT"/config/*.{yml,yaml})
  shopt -u nullglob
  if [[ ${#yaml_files[@]} -gt 0 ]]; then
    log "Checking dynamic YAML in config/..."
    python3 -c '
import sys
try:
    import yaml
except ImportError:
    print("  skip: PyYAML is not installed")
    raise SystemExit(0)
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        yaml.safe_load(fh)
    print(f"  {path}")
' "${yaml_files[@]}"
  fi
fi

log "Recreating Traefik..."
docker compose --env-file "$ROOT/.env" -f "$COMPOSE_FILE" up -d --force-recreate --remove-orphans traefik

log "Waiting for a healthy container..."
for i in $(seq 1 30); do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
  if [[ "$status" == "healthy" ]]; then
    log "Traefik is healthy"
    exit 0
  fi
  sleep 1
  log "  ($i/30) status=${status:-unknown}"
done

die "Traefik did not become healthy. Check: docker logs $CONTAINER"
