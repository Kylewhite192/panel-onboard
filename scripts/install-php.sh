#!/usr/bin/env bash
# Stage: Dependencies
# https://pelican.dev/docs/panel/getting-started#dependencies
#
# Getting Started lists PHP 8.5 (recommended), 8.4, or 8.3 and the extensions
# below, but it does not include apt commands. The only apt snippet in the docs
# that installs those packages is the Upgrading PHP guide:
# https://pelican.dev/docs/guides/php-upgrade#install-php
# The optional `apt purge php*` line from that page is not run here.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

case "${PHP_VERSION}" in
  8.5|8.4|8.3) ;;
  *) die "PHP_VERSION must be 8.5, 8.4, or 8.3 (docs). Got ${PHP_VERSION}." ;;
esac

export DEBIAN_FRONTEND=noninteractive

log "Installing curl, tar, and unzip (required by later panel commands)."
apt-get update
apt-get install -y curl tar unzip ca-certificates gnupg software-properties-common

log "Installing PHP ${PHP_VERSION} from ppa:ondrej/php."
add-apt-repository -y ppa:ondrej/php
apt-get update
apt-get install -y \
  "php${PHP_VERSION}" \
  "php${PHP_VERSION}-gd" \
  "php${PHP_VERSION}-mysql" \
  "php${PHP_VERSION}-mbstring" \
  "php${PHP_VERSION}-bcmath" \
  "php${PHP_VERSION}-xml" \
  "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-zip" \
  "php${PHP_VERSION}-intl" \
  "php${PHP_VERSION}-sqlite3" \
  "php${PHP_VERSION}-fpm"

# The Caddyfile in the docs points at this socket. The docs do not mention
# enabling the unit; without it the socket is not there.
log "Starting php${PHP_VERSION}-fpm."
systemctl enable --now "php${PHP_VERSION}-fpm"
