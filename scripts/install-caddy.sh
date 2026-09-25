#!/usr/bin/env bash
# Installs the Caddy package.
#
# Pelican's web server page assumes Caddy is already installed. It only removes
# /etc/caddy/Caddyfile, writes a new one, and restarts the service. The package
# install below is Caddy's own Debian/Ubuntu instructions:
# https://caddyserver.com/docs/install#debian-ubuntu-raspbian

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

export DEBIAN_FRONTEND=noninteractive

log "Installing Caddy from the official stable repository."
apt-get update
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod o+r /etc/apt/sources.list.d/caddy-stable.list

apt-get update
apt-get install -y caddy
