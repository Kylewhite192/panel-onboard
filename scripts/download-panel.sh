#!/usr/bin/env bash
# Stage: Create Directories & Downloading Files
# https://pelican.dev/docs/panel/getting-started#create-directories--downloading-files

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ -f "${PANEL_DIR}/artisan" ]]; then
  log "${PANEL_DIR} already contains a Pelican panel. Unpacking a release over it mixes old and new files."
  if [[ -t 0 ]]; then
    overwrite="$(ask_yes_no "Unpack this release over that panel?" "0")"
    if [[ "${overwrite}" != "1" ]]; then
      die "Installation aborted."
    fi
  else
    die "${PANEL_DIR} already contains a Pelican panel. Refusing to unpack over it."
  fi
fi

log "Creating ${PANEL_DIR} and downloading the latest panel release."
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
curl -L https://github.com/pelican/panel/releases/latest/download/panel.tar.gz | tar -xzv
