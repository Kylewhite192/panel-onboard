#!/usr/bin/env bash
# Stage: Install Composer
# https://pelican.dev/docs/panel/getting-started#install-composer
# Do not run composer update. The docs say to ignore outdated-dependency notices.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ ! -f "${PANEL_DIR}/composer.json" ]]; then
  die "Panel files are missing in ${PANEL_DIR}. Run scripts/download-panel.sh first."
fi

log "Installing Composer into /usr/local/bin/composer."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

log "Installing panel PHP dependencies."
cd "${PANEL_DIR}"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
