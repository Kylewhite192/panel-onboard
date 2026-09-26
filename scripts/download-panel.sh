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
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
asset_url="$(github_release_asset_url "https://github.com/pelican/panel/releases/latest/download/panel.tar.gz")" \
  || die "Could not resolve the latest panel release."
panel_tag="$(release_tag_from_url "${asset_url}")" || die "Could not read the panel release tag from ${asset_url}."
log "Downloading panel release ${panel_tag}."
curl --proto '=https' --tlsv1.2 -fL --retry 3 -o "${workdir}/panel.tar.gz" "${asset_url}"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "${workdir}/checksum.txt" \
  "https://github.com/pelican/panel/releases/download/${panel_tag}/checksum.txt"
verify_sha256_file "${workdir}/panel.tar.gz" "${workdir}/checksum.txt" "panel.tar.gz"
state_set PANEL_VERSION "${panel_tag}"
log "Panel release ${panel_tag}."
tar -xzf "${workdir}/panel.tar.gz" -C "${PANEL_DIR}"
