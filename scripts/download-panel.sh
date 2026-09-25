#!/usr/bin/env bash
# Stage: Create Directories & Downloading Files
# https://pelican.dev/docs/panel/getting-started#create-directories--downloading-files

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

log "Creating ${PANEL_DIR} and downloading the latest panel release."
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
curl -L https://github.com/pelican/panel/releases/latest/download/panel.tar.gz | tar -xzv
