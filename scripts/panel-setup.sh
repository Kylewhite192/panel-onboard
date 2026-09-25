#!/usr/bin/env bash
# Stage: Panel Setup
# https://pelican.dev/docs/panel/panel-setup
#
# p:environment:setup is interactive. The artisan page lists -n/--no-interaction
# but no flags for the values it asks (URL, timezone, drivers, mail). This script
# runs the documented command and then sets permissions again, because the docs
# chown the tree after setup. Back up APP_KEY from .env when it finishes.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ ! -f "${PANEL_DIR}/artisan" ]]; then
  die "artisan is missing in ${PANEL_DIR}."
fi

log "Running php artisan p:environment:setup."
cd "${PANEL_DIR}"
php artisan p:environment:setup

"$(dirname "$0")/set-permissions.sh"

scheme="http"
if [[ "${PANEL_HTTPS}" == "1" ]]; then
  scheme="https"
fi

log "Back up APP_KEY from ${PANEL_DIR}/.env and store it off this server."
if [[ -n "${PANEL_DOMAIN}" ]]; then
  log "Finish in the browser at ${scheme}://${PANEL_DOMAIN}/installer"
else
  log "Finish in the browser at <domain>/installer or <ip>/installer"
fi
