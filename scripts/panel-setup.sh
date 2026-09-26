#!/usr/bin/env bash
# Stage: Panel Setup
# https://pelican.dev/docs/panel/panel-setup
#
# The current panel release's p:environment:setup copies .env, generates
# APP_KEY, links storage, and caches icons. It does not ask for a URL.
# APP_URL in .env.example is http://panel.test, so this script sets APP_URL
# to the Caddy site. Then it sets permissions, because the docs chown the
# tree after setup. Back up APP_KEY from .env when it finishes.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
if [[ "${INSTALL_DRY_RUN:-0}" == "1" ]]; then
  log "dry-run $(basename "$0")"
  log "dry-run set-permissions.sh"
  exit 0
fi

if [[ ! -f "${PANEL_DIR}/artisan" ]]; then
  die "artisan is missing in ${PANEL_DIR}."
fi

log "Running php artisan p:environment:setup."
if [[ -z "${PANEL_DOMAIN}" && -r /etc/caddy/Caddyfile ]]; then
  site="$(awk '/^[^#[:space:]].*\{$/ { print; exit }' /etc/caddy/Caddyfile)"
  site="${site% \{}"
  if [[ "${site}" == *:80 ]]; then
    PANEL_HTTPS=0
    PANEL_DOMAIN="${site%:80}"
  elif [[ "${site}" == *:443 ]]; then
    PANEL_HTTPS=1
    PANEL_DOMAIN="${site%:443}"
  elif [[ -n "${site}" ]]; then
    PANEL_HTTPS=1
    PANEL_DOMAIN="${site}"
  fi
fi
scheme="http"
if [[ "${PANEL_HTTPS}" == "1" ]]; then
  scheme="https"
fi
cd "${PANEL_DIR}"
php artisan p:environment:setup

if [[ -n "${PANEL_DOMAIN}" ]]; then
  panel_url="${scheme}://${PANEL_DOMAIN}"
  if [[ ! -f .env ]]; then
    die "Expected ${PANEL_DIR}/.env after p:environment:setup."
  fi
  if grep -q '^APP_URL=' .env; then
    sed -i "s|^APP_URL=.*|APP_URL=${panel_url}|" .env
  else
    printf 'APP_URL=%s\n' "${panel_url}" >> .env
  fi
  log "Set APP_URL to ${panel_url}."
fi

bash "$(dirname "$0")/set-permissions.sh"

secrets_save_app_key_file "${PANEL_DIR}/.env"
log "Back up APP_KEY from ${PANEL_DIR}/.env and from ${INSTALLER_SECRETS}."
if [[ -n "${PANEL_DOMAIN}" ]]; then
  log "Finish in the browser at ${scheme}://${PANEL_DOMAIN}/installer"
else
  log "Finish in the browser at <domain>/installer or <ip>/installer"
fi
log "After that installer finishes, run: bash ${ROOT_DIR}/scripts/post-install.sh"
