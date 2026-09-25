#!/usr/bin/env bash
# Pelican Panel installer for Ubuntu 24.04.
# Runs the documented panel stages by calling one script per step.
# Caddy is the web server. Nginx and Apache are not installed.
#
# Required:
#   PANEL_DOMAIN   hostname placed in the Caddyfile (an IP is allowed only for HTTP)
#
# Optional:
#   PANEL_HTTPS=1          write the HTTPS Caddyfile (default 0, HTTP)
#   PANEL_DATABASE=mariadb install MariaDB and create the panel database (default sqlite)
#   PANEL_DB_PASSWORD      password for the pelican MariaDB user
#   PANEL_REDIS=1          install Redis (default 0)
#   PHP_VERSION            8.5 (default), 8.4, or 8.3
#   PANEL_DIR              default /var/www/pelican
#
# php artisan p:environment:setup is interactive, so it is a separate script:
#   sudo ./scripts/panel-setup.sh
# Then open /installer in a browser.

set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"
require_root

if [[ "${INSTALL_DRY_RUN:-0}" != "1" && -z "${PANEL_DOMAIN}" ]]; then
  die "Set PANEL_DOMAIN before running install.sh."
fi

steps=(
  scripts/check-os.sh
  scripts/install-php.sh
  scripts/install-caddy.sh
  scripts/download-panel.sh
  scripts/install-composer.sh
  scripts/configure-caddy.sh
)

if [[ "${PANEL_DATABASE}" == "mariadb" ]]; then
  steps+=(scripts/install-mariadb.sh)
elif [[ "${PANEL_DATABASE}" != "sqlite" ]]; then
  die "PANEL_DATABASE must be sqlite or mariadb."
fi

if [[ "${PANEL_REDIS}" == "1" ]]; then
  steps+=(scripts/install-redis.sh)
fi

steps+=(scripts/set-permissions.sh)

for step in "${steps[@]}"; do
  log "Running ${step}"
  "${ROOT_DIR}/${step}"
done

scheme="http"
if [[ "${PANEL_HTTPS}" == "1" ]]; then
  scheme="https"
fi

log "Panel files, PHP, and Caddy are in place."
log "Next, run: sudo ${ROOT_DIR}/scripts/panel-setup.sh"
log "That command is interactive. When it finishes, back up APP_KEY from ${PANEL_DIR}/.env."
if [[ -n "${PANEL_DOMAIN}" ]]; then
  log "Then open ${scheme}://${PANEL_DOMAIN}/installer"
else
  log "Then open the web installer at /installer"
fi
