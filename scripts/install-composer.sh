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
setup="$(mktemp)"
trap 'rm -f "${setup}"' EXIT
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "${setup}" https://getcomposer.org/installer
# getcomposer.org/installer.sig is a 404. The signature is published here.
expected="$(curl --proto '=https' --tlsv1.2 -fsSL --retry 3 https://composer.github.io/installer.sig | tr -d '[:space:]')"
expected="${expected,,}"
if [[ ! "${expected}" =~ ^[0-9a-f]{96}$ ]]; then
  die "Composer did not publish a SHA384 installer signature."
fi
actual="$(SETUP_FILE="${setup}" php -r 'echo hash_file("sha384", getenv("SETUP_FILE"));')"
actual="${actual,,}"
if [[ "${actual}" != "${expected}" ]]; then
  die "Composer installer signature did not match."
fi
log "Composer installer signature matched."
php "${setup}" --install-dir=/usr/local/bin --filename=composer

log "Installing panel PHP dependencies."
cd "${PANEL_DIR}"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
