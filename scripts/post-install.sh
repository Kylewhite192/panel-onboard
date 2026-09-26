#!/usr/bin/env bash
# After the browser installer, not during install.sh.
# https://pelican.dev/docs/troubleshooting#schedules-not-running
#
# Creates the queue worker with:
#   php artisan p:environment:queue-service --overwrite
# and the www-data cron:
#   * * * * * php <panel>/artisan schedule:run >> /dev/null 2>&1
#
# The Docker image restarts its own supervisor queue worker. This script is
# for the panel installed on the host.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

PANEL_DIR="${PANEL_DIR:-/var/www/pelican}"
if [[ ! -f "${PANEL_DIR}/artisan" ]]; then
  die "artisan is missing in ${PANEL_DIR}."
fi
if [[ ! -f "${PANEL_DIR}/.env" ]] || ! grep -q '^APP_INSTALLED=true' "${PANEL_DIR}/.env"; then
  die "Finish the browser installer first. ${PANEL_DIR}/.env does not set APP_INSTALLED=true."
fi
if ! id www-data >/dev/null 2>&1; then
  die "User www-data does not exist."
fi

dry_run_step

state_init

if ! command -v crontab >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y cron
fi

log "Creating the pelican-queue service."
(
  cd "${PANEL_DIR}"
  php artisan p:environment:queue-service \
    --service-name=pelican-queue \
    --user=www-data \
    --group=www-data \
    --overwrite \
    --no-interaction
)
if [[ ! -f /etc/systemd/system/pelican-queue.service ]]; then
  die "The queue worker unit was not created."
fi
systemctl enable --now pelican-queue

cron_line="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"
current="$(crontab -u www-data -l 2>/dev/null || true)"
if [[ "${current}" == *"artisan schedule:run"* ]]; then
  log "www-data already has a schedule:run cron."
else
  printf '%s\n%s\n' "${current}" "${cron_line}" | sed '/^$/d' | crontab -u www-data -
  log "Installed the schedule:run cron for www-data."
fi

log "Queue worker: systemctl status pelican-queue"
bash "$(dirname "$0")/verify-install.sh" post
