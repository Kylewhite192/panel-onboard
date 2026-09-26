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

export INSTALLER_VERSION=0.1.0-alpha
INSTALLER_STATE_DIR="${INSTALLER_STATE_DIR:-/root/pelican-installer}"
INSTALLER_STATE="${INSTALLER_STATE:-${INSTALLER_STATE_DIR}/state.env}"
INSTALLER_SECRETS="${INSTALLER_SECRETS:-${INSTALLER_STATE_DIR}/secrets.env}"
INSTALLER_SUMMARY="${INSTALLER_SUMMARY:-${INSTALLER_STATE_DIR}/install-summary.txt}"
INSTALLER_LOG="${INSTALLER_LOG:-/var/log/pelican-installer.log}"

# Stderr, because question functions print the answer on stdout and callers capture it.
# The log file is separate and must never receive passwords or APP_KEY.
# While a command is being captured, stderr is already copied into the log.
log() {
  printf '==> %s\n' "$*" >&2
  if [[ "${INSTALLER_LOGGING:-0}" == "1" && "${INSTALLER_CAPTURING:-0}" != "1" ]]; then
    printf '%s %s\n' "$(date -Iseconds)" "$*" >>"${INSTALLER_LOG}"
  fi
}

installer_failure_footer() {
  {
    if [[ -n "${INSTALLER_STAGE:-}" ]]; then
      printf 'Installation failed during: %s\n\n' "${INSTALLER_STAGE}"
    fi
    printf 'Log:\n%s\n\nYou can rerun the installer to resume.\n' "${INSTALLER_LOG}"
  } >&2
  if [[ "${INSTALLER_LOGGING:-0}" == "1" && "${INSTALLER_CAPTURING:-0}" != "1" ]]; then
    {
      if [[ -n "${INSTALLER_STAGE:-}" ]]; then
        printf '%s Installation failed during: %s\n' "$(date -Iseconds)" "${INSTALLER_STAGE}"
      fi
      printf '%s Log: %s\n' "$(date -Iseconds)" "${INSTALLER_LOG}"
      printf '%s You can rerun the installer to resume.\n' "$(date -Iseconds)"
    } >>"${INSTALLER_LOG}"
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  if [[ "${INSTALLER_LOGGING:-0}" == "1" && "${INSTALLER_CAPTURING:-0}" != "1" ]]; then
    printf '%s error: %s\n' "$(date -Iseconds)" "$*" >>"${INSTALLER_LOG}"
  fi
  if [[ "${INSTALLER_LOGGING:-0}" == "1" && "${INSTALLER_DIE_FOOTER:-1}" != "0" ]]; then
    installer_failure_footer
  fi
  exit 1
}

# Literal replace. The secret is not a glob, so a password that contains * stays literal.
literal_redact() {
  local line="$1" secret="$2" out="" prefix
  if [[ -z "${secret}" ]]; then
    printf '%s' "${line}"
    return 0
  fi
  while [[ "${line}" == *"${secret}"* ]]; do
    prefix="${line%%"${secret}"*}"
    out+="${prefix}[redacted]"
    line="${line#*"${secret}"}"
  done
  out+="${line}"
  printf '%s' "${out}"
}

# Drop passwords and application keys from a command transcript.
redact_stream() {
  local line app_key=""
  app_key="$(secrets_get APP_KEY 2>/dev/null || true)"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == *"Generated app key:"* ]]; then
      printf '%s\n' "[redacted application key]"
      continue
    fi
    if [[ "${line}" == *"APP_KEY="* ]]; then
      printf '%s\n' "${line%%APP_KEY=*}APP_KEY=[redacted]"
      continue
    fi
    if [[ -n "${PANEL_DB_PASSWORD:-}" ]]; then
      line="$(literal_redact "${line}" "${PANEL_DB_PASSWORD}")"
    fi
    if [[ -n "${app_key}" && "${app_key}" != "base64:" ]]; then
      line="$(literal_redact "${line}" "${app_key}")"
    fi
    printf '%s\n' "${line}"
  done
}

# Run a command. Its output goes to the terminal and, on a real install, the log.
# The terminal copy is stderr so a captured Gum answer cannot include it.
run_captured() {
  local status
  local -a pipe_status
  if [[ "${INSTALLER_LOGGING:-0}" != "1" ]]; then
    "$@" >&2
    return
  fi
  export INSTALLER_CAPTURING=1
  set +e
  "$@" 2>&1 | redact_stream | tee -a "${INSTALLER_LOG}" >&2
  pipe_status=("${PIPESTATUS[@]}")
  set -e
  INSTALLER_CAPTURING=0
  export INSTALLER_CAPTURING
  status="${pipe_status[0]}"
  if [[ "${pipe_status[2]:-0}" -ne 0 && "${status}" -eq 0 ]]; then
    printf 'error: could not write %s\n' "${INSTALLER_LOG}" >&2
    return 1
  fi
  return "${status}"
}

# Tag from a GitHub release asset URL after curl has followed /releases/latest.
release_tag_from_url() {
  local url="$1" tag
  tag="${url##*/download/}"
  tag="${tag%%/*}"
  if [[ -z "${tag}" || "${tag}" == "${url}" || "${tag}" == */* ]]; then
    return 1
  fi
  printf '%s' "${tag}"
}

# checksum file lines look like: <sha256>  <filename>
verify_sha256_file() {
  local file="$1" sums="$2" name="$3" line hash actual
  line="$(grep -F "${name}" "${sums}" | head -n 1 || true)"
  if [[ -z "${line}" ]]; then
    die "Checksum file has no entry for ${name}."
  fi
  hash="${line%%[[:space:]]*}"
  hash="${hash#sha256:}"
  hash="${hash,,}"
  if [[ ! "${hash}" =~ ^[0-9a-f]{64}$ ]]; then
    die "Checksum file has no SHA256 for ${name}."
  fi
  actual="$(sha256sum "${file}" | awk '{ print $1 }')"
  actual="${actual,,}"
  if [[ "${actual}" != "${hash}" ]]; then
    die "SHA256 mismatch for ${name}."
  fi
  log "SHA256 matched ${name}."
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
