#!/usr/bin/env bash
# Installs Nginx from Ubuntu.
# https://pelican.dev/docs/panel/webserver-config
#
# The docs remove /etc/nginx/sites-enabled/default before the Pelican site is
# enabled. Caddy is stopped when it is running so it does not keep port 80.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

export DEBIAN_FRONTEND=noninteractive

log "Installing Nginx."
apt-get update
apt-get install -y nginx

if [[ -e /etc/nginx/sites-enabled/default ]]; then
  log "Removing the default Nginx site."
  rm -f /etc/nginx/sites-enabled/default
fi

if systemctl is-active --quiet caddy; then
  log "Stopping Caddy so Nginx can use port 80."
  systemctl disable --now caddy
fi
