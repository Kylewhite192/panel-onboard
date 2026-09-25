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

# /run/systemd/system exists only when systemd is the running init.
# An imported WSL rootfs boots WSL's own init until wsl.conf asks for systemd.
if [[ ! -d /run/systemd/system ]]; then
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
    conf="/etc/wsl.conf"
    if [[ -f "${conf}" ]] && grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$' "${conf}"; then
      :
    elif [[ -f "${conf}" ]] && grep -Eq '^[[:space:]]*systemd[[:space:]]*=' "${conf}"; then
      sed -i -E 's/^[[:space:]]*systemd[[:space:]]*=.*/systemd=true/' "${conf}"
    elif [[ -f "${conf}" ]] && grep -Eq '^[[:space:]]*\[boot\][[:space:]]*$' "${conf}"; then
      sed -i -E '/^[[:space:]]*\[boot\][[:space:]]*$/a systemd=true' "${conf}"
    else
      printf '\n[boot]\nsystemd=true\n' >>"${conf}"
    fi
    die "systemd is not running, so systemctl cannot start services. systemd=true is now set in /etc/wsl.conf. Close this session, and from Windows run: wsl --terminate ${WSL_DISTRO_NAME:-<distro-name>}   Then start the distro and run the installer again."
  fi
  die "systemd is not running. This installer starts services with systemctl."
fi
