#!/usr/bin/env bash
# Optional UFW rules for the mode that was just installed.
# Panel and Docker publish 80 and 443. Wings listens on 8080, and its SFTP
# server listens on 2022. The SSH port from this session and from sshd is
# allowed before UFW is enabled. 22 is the fallback when neither is known.
# Game allocation ports are chosen later in the panel and are not opened here.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

export DEBIAN_FRONTEND=noninteractive

add_ssh_port() {
  local port="$1"
  if [[ "${port}" =~ ^[0-9]+$ ]] && (( 10#${port} >= 1 && 10#${port} <= 65535 )); then
    ssh_ports+=("${port}")
  fi
}

ssh_ports=()
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  # client_ip client_port server_ip server_port
  read -r _client_ip _client_port _server_ip ssh_server_port <<<"${SSH_CONNECTION}"
  add_ssh_port "${ssh_server_port}"
fi
if sshd_config="$(sshd -T 2>/dev/null)"; then
  while read -r key value _; do
    if [[ "${key}" == "port" ]]; then
      add_ssh_port "${value}"
    fi
  done <<<"${sshd_config}"
fi
if [[ ${#ssh_ports[@]} -eq 0 ]]; then
  ssh_ports+=(22)
fi
log "SSH ports that stay open: ${ssh_ports[*]}"
ports=("${ssh_ports[@]}")
dry_run_step

case "${INSTALL_MODE}" in
  panel|both|docker|docker-proxy)
    ports+=(80 443)
    ;;
  *) ;;
esac

case "${INSTALL_MODE}" in
  wings|both)
    ports+=(8080 2022)
    ;;
  *) ;;
esac

if [[ "${PANEL_CERTBOT}" == "1" ]]; then
  ports+=(80)
fi

log "Installing UFW."
apt-get update
apt-get install -y ufw

seen=" "
unique=()
for port in "${ports[@]}"; do
  if [[ "${seen}" != *" ${port} "* ]]; then
    seen="${seen}${port} "
    unique+=("${port}")
  fi
done

for port in "${unique[@]}"; do
  log "Allowing ${port}/tcp."
  ufw allow "${port}/tcp"
done

log "Enabling UFW."
ufw --force enable
log "Game server ports are not opened. Add those allocation ports in UFW when you create them."
