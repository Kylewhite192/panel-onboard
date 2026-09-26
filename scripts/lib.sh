#!/usr/bin/env bash
# Shared helpers for the Pelican panel installer.
# Stage order follows the panel docs shipped in docs-main (same text as pelican.dev).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL_DIR="${PANEL_DIR:-/var/www/pelican}"
PHP_VERSION="${PHP_VERSION:-8.5}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"
# 0 writes the documented HTTP site. 1 writes the documented HTTPS site.
PANEL_HTTPS="${PANEL_HTTPS:-0}"
# caddy (default) or nginx. Docker modes keep the image's Caddy.
PANEL_WEBSERVER="${PANEL_WEBSERVER:-caddy}"
# sqlite (default in the docs) or mariadb.
PANEL_DATABASE="${PANEL_DATABASE:-sqlite}"
# 1 installs Redis from the advanced guide. The web installer still receives the Redis settings.
PANEL_REDIS="${PANEL_REDIS:-0}"

INSTALLER_VERSION=0.1.0
INSTALLER_STATE_DIR="${INSTALLER_STATE_DIR:-/root/pelican-installer}"
INSTALLER_STATE="${INSTALLER_STATE:-${INSTALLER_STATE_DIR}/state.env}"
INSTALLER_SECRETS="${INSTALLER_SECRETS:-${INSTALLER_STATE_DIR}/secrets.env}"
INSTALLER_SUMMARY="${INSTALLER_SUMMARY:-${INSTALLER_STATE_DIR}/install-summary.txt}"
INSTALLER_LOG="${INSTALLER_LOG:-/var/log/pelican-installer.log}"

# Stderr, because question functions print the answer on stdout and callers capture it.
# The log file is separate and must never receive passwords or APP_KEY.
log() {
  printf '==> %s\n' "$*" >&2
  if [[ "${INSTALLER_LOGGING:-0}" == "1" ]]; then
    printf '%s %s\n' "$(date -Iseconds)" "$*" >>"${INSTALLER_LOG}"
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  if [[ "${INSTALLER_LOGGING:-0}" == "1" ]]; then
    printf '%s error: %s\n' "$(date -Iseconds)" "$*" >>"${INSTALLER_LOG}"
  fi
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

# Nginx's fastcgi_pass value. Caddy uses php_fpm_socket, which has a different unix prefix.
nginx_fpm_socket() {
  printf 'unix:/run/php/php%s-fpm.sock' "${PHP_VERSION}"
}

# First IPv4 from hostname -I, or 127.0.0.1 when the host has no other address.
# Pressing Enter at the install prompt keeps this value.
default_panel_domain() {
  local ip
  while read -r ip; do
    if is_ip_address "${ip}" && [[ "${ip}" != 127.* ]]; then
      printf '%s' "${ip}"
      return
    fi
  done < <(hostname -I 2>/dev/null | tr ' ' '\n' || true)
  printf '%s' "127.0.0.1"
}

is_ip_address() {
  local octet
  [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
    if (( 10#${octet} > 255 )); then
      return 1
    fi
  done
}

# Value safe to place inside a MariaDB single-quoted string.
# Backslash is escaped first because MariaDB treats \ as an escape.
sql_escape() {
  local value="$1"
  if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* ]]; then
    die "The database password cannot contain a newline."
  fi
  value="${value//\\/\\\\}"
  value="${value//\'/\'\'}"
  printf '%s' "${value}"
}

reject_ip_with_https() {
  if [[ "${PANEL_HTTPS}" == "1" ]] && is_ip_address "${PANEL_DOMAIN}"; then
    die "The docs say IPs cannot be used with SSL. Use a hostname or set PANEL_HTTPS=0."
  fi
}

# Questions live in lib/. Stage scripts only read the exported variables.
# shellcheck source=../lib/ui.sh
source "${ROOT_DIR}/lib/ui.sh"
# shellcheck source=../lib/prompts.sh
source "${ROOT_DIR}/lib/prompts.sh"
# shellcheck source=../lib/state.sh
source "${ROOT_DIR}/lib/state.sh"
