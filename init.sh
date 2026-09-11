#!/usr/bin/env bash
# Prepare local files so this stack can start from .env alone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: ./init.sh [--prepare-only] [--up]

  (default)       Create .env if missing, write dashboard auth, create dirs
  --prepare-only  Same as default (used by reload.sh)
  --up            Prepare files, then start Traefik
EOF
}

log() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

load_env() {
  [[ -f "$ROOT/.env" ]] || die ".env is missing. Copy .env.example to .env and edit it."
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
}

migrate_legacy_acme() {
  if [[ -f "$ROOT/traefik/acme.json" && ! -f "$ROOT/traefik/letsencrypt/acme.json" ]]; then
    mkdir -p "$ROOT/traefik/letsencrypt"
    mv "$ROOT/traefik/acme.json" "$ROOT/traefik/letsencrypt/acme.json"
    chmod 600 "$ROOT/traefik/letsencrypt/acme.json"
    log "Moved legacy traefik/acme.json → traefik/letsencrypt/acme.json"
  fi
}

ensure_dirs() {
  mkdir -p "$ROOT/config" "$ROOT/traefik/letsencrypt" "$ROOT/traefik/auth"
}

write_dashboard_users() {
  local dest="$ROOT/traefik/auth/users"
  [[ -n "${DASHBOARD_USER:-}" ]] || die "DASHBOARD_USER is empty in .env"
  [[ -n "${DASHBOARD_PASSWORD:-}" ]] || die "DASHBOARD_PASSWORD is empty in .env"

  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -cbB "$dest" "$DASHBOARD_USER" "$DASHBOARD_PASSWORD" >/dev/null 2>&1
  elif command -v openssl >/dev/null 2>&1; then
    local hash
    hash="$(openssl passwd -apr1 "$DASHBOARD_PASSWORD")"
    printf '%s:%s\n' "$DASHBOARD_USER" "$hash" > "$dest"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm httpd:2.4-alpine \
      htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASSWORD" > "$dest"
  else
    die "Need htpasswd, openssl, or docker to hash DASHBOARD_PASSWORD"
  fi

  chmod 600 "$dest"
  log "Wrote $dest"
}

prepare() {
  if [[ ! -f "$ROOT/.env" ]]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    log "Created .env from .env.example — edit it before starting Traefik."
  fi

  load_env
  migrate_legacy_acme
  ensure_dirs
  write_dashboard_users

  if [[ "${DASHBOARD_PASSWORD}" == "change-me-now" ]]; then
    warn "DASHBOARD_PASSWORD is still the example value. Change it in .env and re-run ./init.sh"
  fi
  if [[ "${PRIMARY_DOMAIN}" == "example.com" ]]; then
    warn "PRIMARY_DOMAIN is still example.com"
  fi
}

start_stack() {
  docker compose --env-file "$ROOT/.env" -f "$ROOT/docker-compose.yml" up -d
  log "Traefik is starting. Dashboard: https://traefik.${PRIMARY_DOMAIN}"
}

DO_UP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare-only) shift ;;
    --up) DO_UP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
done

prepare
if [[ "$DO_UP" -eq 1 ]]; then
  start_stack
fi
