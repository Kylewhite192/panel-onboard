#!/usr/bin/env bash
# Stage: Picking an Operating System (OS)
# https://pelican.dev/docs/panel/getting-started#picking-an-operating-system-os
# Ubuntu 24.04 is marked supported. This installer is written for that release only.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ ! -r /etc/os-release ]]; then
  die "Cannot read /etc/os-release."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
  die "This installer targets Ubuntu 24.04. This host is ${PRETTY_NAME:-unknown}."
fi

log "Ubuntu 24.04 detected."
