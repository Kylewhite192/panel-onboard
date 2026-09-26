#!/usr/bin/env bash
# Let's Encrypt certificate for Wings.
# https://pelican.dev/docs/guides/ssl
#
# A Wings host with no web server uses: certbot certonly --standalone -d <hostname>
# --non-interactive --agree-tos --email are Certbot's flags for that command
# without a prompt. The 23:00 cron is the renewal line from the same page,
# with the deploy hook restarting wings.
# Standalone renewal binds port 80. The pre and post hooks saved on this
# certificate stop Caddy or Nginx for that attempt and start them again.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ -z "${WINGS_DOMAIN:-}" || -z "${CERTBOT_EMAIL:-}" ]]; then
  die "Certbot needs WINGS_DOMAIN and CERTBOT_EMAIL."
fi
if is_ip_address "${WINGS_DOMAIN}"; then
  die "Let's Encrypt needs a hostname, not an IP."
fi

export DEBIAN_FRONTEND=noninteractive
log "Installing Certbot."
apt-get update
apt-get install -y certbot

stopped_caddy=0
stopped_nginx=0
restore_web() {
  if [[ "${stopped_caddy}" == "1" ]]; then
    log "Starting Caddy."
    systemctl start caddy || true
    stopped_caddy=0
  fi
  if [[ "${stopped_nginx}" == "1" ]]; then
    log "Starting Nginx."
    systemctl start nginx || true
    stopped_nginx=0
  fi
}
trap restore_web EXIT

if systemctl is-active --quiet caddy; then
  log "Stopping Caddy so Certbot can bind port 80."
  systemctl stop caddy
  stopped_caddy=1
fi
if systemctl is-active --quiet nginx; then
  log "Stopping Nginx so Certbot can bind port 80."
  systemctl stop nginx
  stopped_nginx=1
fi

log "Requesting a certificate for ${WINGS_DOMAIN}."
# Saved on this certificate only, so a later `certbot renew` does not stop
# Nginx for the panel certificate that uses the Nginx plugin.
pre_hook='rm -f /run/pelican-certbot-stopped; for s in caddy nginx; do if systemctl is-active --quiet "$s"; then systemctl stop "$s" && printf "%s\n" "$s" >> /run/pelican-certbot-stopped; fi; done'
post_hook='if [ -s /run/pelican-certbot-stopped ]; then while read -r s; do systemctl start "$s" || true; done < /run/pelican-certbot-stopped; rm -f /run/pelican-certbot-stopped; fi'
certbot certonly --standalone --non-interactive --agree-tos \
  --email "${CERTBOT_EMAIL}" -d "${WINGS_DOMAIN}" --keep-until-expiring \
  --pre-hook "${pre_hook}" \
  --post-hook "${post_hook}" \
  --deploy-hook "systemctl restart wings"

cron_line='0 23 * * * certbot renew --quiet --deploy-hook "systemctl restart wings"'
current="$(crontab -l 2>/dev/null || true)"
if [[ "${current}" != *"systemctl restart wings"* ]]; then
  printf '%s\n%s\n' "${current}" "${cron_line}" | sed '/^$/d' | crontab -
  log "Installed the 23:00 renewal cron from the SSL guide."
else
  log "A certbot renew cron entry is already installed."
fi

log "Certificate: /etc/letsencrypt/live/${WINGS_DOMAIN}/fullchain.pem"
log "Private key: /etc/letsencrypt/live/${WINGS_DOMAIN}/privkey.pem"
