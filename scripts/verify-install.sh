#!/usr/bin/env bash
# Confirms the choices from this run are actually in effect.
# Wings is installed and left stopped until /etc/pelican/config.yml exists.
# The browser installer, queue worker, and scheduler are checked only when
# this script is run as: verify-install.sh post

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

state_load_choices
verify_mode="${1:-install}"
checks_failed=0

install -d -m 700 "${INSTALLER_STATE_DIR}"
if [[ "${verify_mode}" == "post" ]]; then
  printf '\nAfter the browser installer\n' >>"${INSTALLER_SUMMARY}"
else
  : >"${INSTALLER_SUMMARY}"
  chmod 600 "${INSTALLER_SUMMARY}"
  {
    printf 'Pelican installation verification\n'
    printf 'Installer version: %s\n' "${INSTALLER_VERSION}"
    printf 'Mode: %s\n' "${INSTALL_MODE:-unknown}"
  } >>"${INSTALLER_SUMMARY}"
fi

record_check() {
  local line="$1"
  printf '%s\n' "${line}" >&2
  printf '%s\n' "${line}" >>"${INSTALLER_SUMMARY}"
  if [[ "${INSTALLER_LOGGING:-0}" == "1" ]]; then
    printf '%s %s\n' "$(date -Iseconds)" "${line}" >>"${INSTALLER_LOG}"
  fi
}

pass_check() {
  record_check "✓ $1"
}

fail_check() {
  record_check "✗ $1"
  checks_failed=1
}

service_check() {
  local label="$1" unit="$2"
  if systemctl is-active --quiet "${unit}"; then
    pass_check "${label}"
  else
    fail_check "${label}"
  fi
}

http_check() {
  local url="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${url}" || true)"
  if [[ "${code}" =~ ^[0-9]+$ ]] && (( code >= 200 && code < 400 )); then
    pass_check "Panel responds at ${url} (HTTP ${code})"
  elif [[ -z "${code}" || "${code}" == "000" ]]; then
    fail_check "Panel did not respond at ${url}"
  else
    fail_check "Panel returned HTTP ${code} at ${url}"
  fi
}

panel_url() {
  local scheme="http"
  if [[ "${PANEL_HTTPS:-0}" == "1" ]]; then
    scheme="https"
  fi
  if [[ -n "${PANEL_DOMAIN:-}" ]]; then
    printf '%s://%s' "${scheme}" "${PANEL_DOMAIN}"
  fi
}

if [[ "${verify_mode}" == "post" ]]; then
  panel_env="${PANEL_DIR:-/var/www/pelican}/.env"
  if [[ -f "${panel_env}" ]] && grep -q '^APP_INSTALLED=true' "${panel_env}"; then
    pass_check "Browser installation completed"
  else
    fail_check "Browser installation completed"
  fi
  service_check "Queue worker running" pelican-queue
  cron_now="$(crontab -u www-data -l 2>/dev/null || true)"
  if [[ "${cron_now}" == *"artisan schedule:run"* ]]; then
    pass_check "Scheduler installed"
  else
    fail_check "Scheduler installed"
  fi
  app_url="$(grep '^APP_URL=' "${panel_env}" | tail -n 1 || true)"
  app_url="${app_url#APP_URL=}"
  app_url="${app_url%\"}"
  app_url="${app_url#\"}"
  if [[ -n "${app_url}" ]]; then
    http_check "${app_url}"
  else
    fail_check "Panel URL is set"
  fi
else
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
    pass_check "Ubuntu 24.04"
  else
    fail_check "Ubuntu 24.04"
  fi
  if [[ -d /run/systemd/system ]]; then
    pass_check "systemd running"
  else
    fail_check "systemd running"
  fi

  case "${INSTALL_MODE:-}" in
    panel|both)
      service_check "PHP ${PHP_VERSION} FPM running" "php${PHP_VERSION}-fpm"
      if [[ -f "${PANEL_DIR}/artisan" ]]; then
        pass_check "Panel files present"
      else
        fail_check "Panel files present"
      fi
      if [[ -f "${PANEL_DIR}/.env" ]] && grep -q '^APP_URL=' "${PANEL_DIR}/.env"; then
        pass_check "Panel environment configured"
      else
        fail_check "Panel environment configured"
      fi
      if [[ "${PANEL_WEBSERVER}" == "nginx" ]]; then
        service_check "Nginx running" nginx
      else
        service_check "Caddy running" caddy
      fi
      if [[ "${PANEL_DATABASE}" == "mariadb" ]]; then
        service_check "MariaDB running" mariadb
      fi
      if [[ "${PANEL_REDIS:-0}" == "1" ]]; then
        service_check "Redis running" redis-server
      fi
      site_url="$(panel_url)"
      if [[ -n "${site_url}" ]]; then
        http_check "${site_url}/installer"
      fi
      ;;
  esac

  case "${INSTALL_MODE:-}" in
    wings|both|docker|docker-proxy)
      service_check "Docker running" docker
      ;;
  esac

  case "${INSTALL_MODE:-}" in
    docker|docker-proxy)
      if [[ -n "${DOCKER_DIR:-}" && -f "${DOCKER_DIR}/compose.yml" ]]; then
        running="$(cd "${DOCKER_DIR}" && docker compose ps --status running -q || true)"
        if [[ -n "${running}" ]]; then
          pass_check "Panel container running"
        else
          fail_check "Panel container running"
        fi
      else
        fail_check "Panel container running"
      fi
      if [[ -n "${APP_URL:-}" ]]; then
        http_check "${APP_URL}/installer"
      fi
      ;;
  esac

  case "${INSTALL_MODE:-}" in
    wings|both)
      if [[ -x /usr/local/bin/wings && -f /etc/systemd/system/wings.service ]]; then
        pass_check "Wings binary installed (service left stopped until config.yml exists)"
      else
        fail_check "Wings binary installed"
      fi
      ;;
  esac

  if [[ "${PANEL_FIREWALL:-0}" == "1" ]]; then
    if ufw status | grep -q 'Status: active'; then
      pass_check "UFW configured"
    else
      fail_check "UFW configured"
    fi
  fi

  if [[ "${PANEL_CERTBOT:-0}" == "1" && -n "${WINGS_DOMAIN:-}" ]]; then
    if [[ -f "/etc/letsencrypt/live/${WINGS_DOMAIN}/fullchain.pem" ]]; then
      pass_check "Wings certificate present"
    else
      fail_check "Wings certificate present"
    fi
  fi

  printf '\n' >>"${INSTALLER_SUMMARY}"
  site_url="$(panel_url)"
  if [[ "${INSTALL_MODE:-}" == "docker" || "${INSTALL_MODE:-}" == "docker-proxy" ]]; then
    site_url="${APP_URL:-}"
  fi
  if [[ -n "${site_url}" ]]; then
    record_check "Panel:"
    record_check "${site_url}/installer"
  fi
fi

chmod 600 "${INSTALLER_SUMMARY}"
if [[ "${checks_failed}" -ne 0 ]]; then
  if [[ "${verify_mode}" == "post" ]]; then
    state_set stage_post_install failed
  else
    state_set stage_verify failed
  fi
  die "Verification failed. The summary is ${INSTALLER_SUMMARY}."
fi
if [[ "${verify_mode}" == "post" ]]; then
  record_check "Browser installation checks passed."
  state_set stage_post_install complete
else
  record_check "Installation preparation completed successfully."
  record_check "Summary: ${INSTALLER_SUMMARY}"
  state_set stage_verify complete
fi
