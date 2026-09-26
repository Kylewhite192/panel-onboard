#!/usr/bin/env bash
# Docker CE, stable channel.
# https://pelican.dev/docs/wings/install#installing-docker
# The same engine is required for the panel Docker compose file.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if docker compose version >/dev/null 2>&1; then
  log "Docker Compose is already installed."
  systemctl enable --now docker
  exit 0
fi

log "Installing Docker CE from https://get.docker.com/ (stable channel)."
curl --proto '=https' --tlsv1.2 -fsSL https://get.docker.com/ | CHANNEL=stable sh
systemctl enable --now docker
docker compose version >/dev/null
