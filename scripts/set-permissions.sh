#!/usr/bin/env bash
# Stage: Setting Permissions
# https://pelican.dev/docs/panel/panel-setup#setting-permissions
# Ubuntu uses the NGINX/Apache/Caddy tab: www-data.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ ! -d "${PANEL_DIR}/storage" || ! -d "${PANEL_DIR}/bootstrap/cache" ]]; then
  die "Expected ${PANEL_DIR}/storage and bootstrap/cache. Download the panel first."
fi

log "Setting panel file permissions."
cd "${PANEL_DIR}"
shopt -s nullglob
storage_entries=(storage/*)
if ((${#storage_entries[@]} == 0)); then
  die "storage/ is empty, so the documented chmod of storage/* has nothing to match."
fi
chmod -R 755 "${storage_entries[@]}" bootstrap/cache/
chown -R www-data:www-data "${PANEL_DIR}"
