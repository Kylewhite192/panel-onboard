#!/usr/bin/env bash
# Stage: Installing Wings, plus the systemd unit from Daemonizing.
# https://pelican.dev/docs/wings/install
#
# The unit is installed and not started. Wings exits until /etc/pelican/config.yml
# exists, and the docs say to run wings --debug before systemctl enable --now.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ "${WINGS_VIRT_CHECKED:-0}" != "1" ]]; then
  confirm_wings_host
fi

arch="arm64"
if [[ "$(uname -m)" == "x86_64" ]]; then
  arch="amd64"
fi

log "Creating /etc/pelican and /var/run/wings."
mkdir -p /etc/pelican /var/run/wings

log "Downloading Wings (${arch})."
curl -fL -o /usr/local/bin/wings \
  "https://github.com/pelican/wings/releases/latest/download/wings_linux_${arch}"
chmod u+x /usr/local/bin/wings

log "Writing /etc/systemd/system/wings.service."
cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

log "Create a node in the panel and save its Configuration tab to /etc/pelican/config.yml."
log "The node's Auto Deploy command can write that file for you."
if [[ "${PANEL_CERTBOT}" == "1" ]]; then
  log "Use the Certbot files under /etc/letsencrypt/live/${WINGS_DOMAIN}/ for the node SSL paths."
else
  log "If the panel uses HTTPS, Wings must use SSL too. See https://pelican.dev/docs/guides/ssl"
fi
log "After config.yml is in place, test with: wings --debug"
log "Then start it with: systemctl enable --now wings"
