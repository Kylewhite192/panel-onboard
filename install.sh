#!/usr/bin/env bash
# Pelican installer for Ubuntu 24.04.
# install.sh asks what to install with gum, then runs one script per stage.
#
# Modes:
#   panel         PHP-FPM on this machine, with Caddy or Nginx
#   wings         Docker CE and the Wings binary
#   both          panel, then wings
#   docker        official panel compose file
#   docker-proxy  official compose file plus the reverse-proxy Caddyfile
#
# Environment variables pre-fill the suggestions:
#   INSTALL_MODE, PANEL_DOMAIN, PANEL_HTTPS, PANEL_WEBSERVER, PHP_VERSION, PANEL_DATABASE,
#   PANEL_DB_PASSWORD, PANEL_REDIS, PANEL_DIR, PANEL_FIREWALL, PANEL_CERTBOT,
#   WINGS_DOMAIN, CERTBOT_EMAIL, APP_URL, ADMIN_EMAIL, DOCKER_DIR,
#   DOCKER_UPSTREAM_IP

set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"
require_root
prompt_install_options

# bash, not a direct exec, so the stage scripts work when a zip stores them
# without the executable bit.
run_step() {
  log "Running $1"
  bash "${ROOT_DIR}/$1"
}

run_panel() {
  local step
  local steps=(
    scripts/check-os.sh
    scripts/install-php.sh
  )

  case "${PANEL_WEBSERVER}" in
    caddy) steps+=(scripts/install-caddy.sh) ;;
    nginx) steps+=(scripts/install-nginx.sh) ;;
    *) die "PANEL_WEBSERVER must be caddy or nginx." ;;
  esac

  steps+=(
    scripts/download-panel.sh
    scripts/install-composer.sh
  )

  if [[ "${PANEL_WEBSERVER}" == "nginx" ]]; then
    steps+=(scripts/configure-nginx.sh)
  else
    steps+=(scripts/configure-caddy.sh)
  fi

  if [[ "${PANEL_DATABASE}" == "mariadb" ]]; then
    steps+=(scripts/install-mariadb.sh)
  elif [[ "${PANEL_DATABASE}" != "sqlite" ]]; then
    die "PANEL_DATABASE must be sqlite or mariadb."
  fi

  if [[ "${PANEL_REDIS}" == "1" ]]; then
    steps+=(scripts/install-redis.sh)
  fi

  for step in "${steps[@]}"; do
    run_step "${step}"
  done

  # Permissions run after environment setup, which is the order in the docs.
  run_step scripts/panel-setup.sh
}

run_wings() {
  if [[ "${INSTALL_MODE}" == "wings" ]]; then
    run_step scripts/check-os.sh
  fi
  run_step scripts/install-docker-engine.sh
  run_step scripts/install-wings.sh
}

case "${INSTALL_MODE}" in
  panel)
    run_panel
    ;;
  wings)
    run_wings
    ;;
  both)
    run_panel
    run_wings
    ;;
  docker|docker-proxy)
    run_step scripts/check-os.sh
    run_step scripts/install-docker-engine.sh
    run_step scripts/install-panel-docker.sh
    ;;
  *)
    die "INSTALL_MODE must be panel, wings, both, docker, or docker-proxy."
    ;;
esac

if [[ "${PANEL_FIREWALL}" == "1" ]]; then
  run_step scripts/configure-firewall.sh
fi

# After UFW, so port 80 is already allowed when the firewall was requested.
if [[ "${PANEL_CERTBOT}" == "1" ]]; then
  run_step scripts/install-certbot.sh
fi
