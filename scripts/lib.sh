#!/usr/bin/env bash
# Shared helpers for the Pelican panel installer.
# Stage order follows the panel docs shipped in docs-main (same text as pelican.dev).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL_DIR="${PANEL_DIR:-/var/www/pelican}"
PHP_VERSION="${PHP_VERSION:-8.5}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"
# 0 writes the documented HTTP Caddyfile. 1 writes the documented HTTPS Caddyfile.
PANEL_HTTPS="${PANEL_HTTPS:-0}"
# sqlite (default in the docs) or mariadb.
PANEL_DATABASE="${PANEL_DATABASE:-sqlite}"
# 1 installs Redis from the advanced guide. The web installer still receives the Redis settings.
PANEL_REDIS="${PANEL_REDIS:-0}"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${INSTALL_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run this installer as root."
  fi
}

dry_run_step() {
  if [[ "${INSTALL_DRY_RUN:-0}" == "1" ]]; then
    log "dry-run $(basename "$0")"
    exit 0
  fi
}

php_fpm_socket() {
  printf 'unix//run/php/php%s-fpm.sock' "${PHP_VERSION}"
}
