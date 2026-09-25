#!/usr/bin/env bash
# Stage: Install Redis
# https://pelican.dev/docs/panel/advanced/redis#install-redis
#
# The docs say not to run php artisan p:redis:setup on a first install.
# Enter Redis in the web installer.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

log "Installing Redis."
apt-get install -y lsb-release curl gpg
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
  | tee /etc/apt/sources.list.d/redis.list >/dev/null
apt-get update -y
apt-get install -y redis-server
systemctl enable --now redis-server
