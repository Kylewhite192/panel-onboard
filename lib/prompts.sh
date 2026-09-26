#!/usr/bin/env bash
# Install questions. lib/ui.sh asks them with gum.

# Wings docs: modified grs/mod kernels cannot run Docker, and OpenVZ/LXC usually cannot.
confirm_wings_host() {
  local kernel virt proceed
  kernel="$(uname -r)"
  if [[ "${kernel}" == *-grs-ipv6-64 || "${kernel}" == *-mod-std-ipv6-64 ]]; then
    die "Kernel ${kernel} is the unsupported modified kernel from the Wings docs. Ask the host for an unmodified kernel."
  fi
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  case "${virt}" in
    *openvz*|*ovz*|*lxc*)
      printf 'warning: %s virtualization usually cannot run Docker. The Wings docs say to confirm nested virtualization with the provider.\n' "${virt}" >&2
      proceed="$(ask_yes_no "Continue anyway?" "0")"
      if [[ "${proceed}" != "1" ]]; then
        die "Installation aborted."
      fi
      ;;
    *)
      if [[ -n "${virt}" && "${virt}" != "none" ]]; then
        log "Virtualization: ${virt}"
      fi
      ;;
  esac
  WINGS_VIRT_CHECKED=1
  export WINGS_VIRT_CHECKED
}

prompt_panel_options() {
  if [[ -z "${PANEL_DOMAIN}" ]]; then
    PANEL_DOMAIN="$(default_panel_domain)"
  fi

  while true; do
    PANEL_DOMAIN="$(ask "Preferred IP or domain name" "${PANEL_DOMAIN}")"
    PANEL_HTTPS="$(ask_yes_no "Use HTTPS" "${PANEL_HTTPS}")"
    if [[ "${PANEL_HTTPS}" == "1" ]] && is_ip_address "${PANEL_DOMAIN}"; then
      printf 'error: The docs say IPs cannot be used with SSL. Enter a hostname, or answer no to HTTPS.\n' >&2
      PANEL_HTTPS=0
      continue
    fi
    break
  done

  PANEL_WEBSERVER="$(ui_menu "Web server" "${PANEL_WEBSERVER:-caddy}" \
    "caddy|Caddy" \
    "nginx|Nginx")"

  if [[ "${PANEL_WEBSERVER}" == "nginx" && "${PANEL_HTTPS}" == "1" ]]; then
    CERTBOT_EMAIL="$(ask_email "Email for Let's Encrypt" "${CERTBOT_EMAIL:-}")"
    export CERTBOT_EMAIL
  fi

  PHP_VERSION="$(ui_menu "PHP version" "${PHP_VERSION}" \
    "8.5|PHP 8.5" \
    "8.4|PHP 8.4" \
    "8.3|PHP 8.3")"

  PANEL_DATABASE="$(ui_menu "Database" "${PANEL_DATABASE}" \
    "sqlite|SQLite" \
    "mariadb|MariaDB")"

  if [[ "${PANEL_DATABASE}" == "mariadb" ]]; then
    if [[ -n "${PANEL_DB_PASSWORD:-}" ]]; then
      password_default="enter"
    else
      password_default="generate"
    fi
    password_choice="$(ui_menu "MariaDB password for pelican@127.0.0.1" "${password_default}" \
      "generate|Generate a password" \
      "enter|Enter a password")"
    if [[ "${password_choice}" == "generate" ]]; then
      if ! command -v openssl >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update >&2
        apt-get install -y openssl >&2
      fi
      PANEL_DB_PASSWORD="$(openssl rand -hex 32)"
      printf 'MariaDB password for pelican@127.0.0.1: %s\n' "${PANEL_DB_PASSWORD}" >&2
      printf 'Saved in %s\n' "${INSTALLER_SECRETS}" >&2
    else
      PANEL_DB_PASSWORD="$(ask_password)"
    fi
    secrets_set PANEL_DB_PASSWORD "${PANEL_DB_PASSWORD}"
    export PANEL_DB_PASSWORD
  fi

  PANEL_REDIS="$(ask_yes_no "Install Redis" "${PANEL_REDIS}")"
  PANEL_DIR="$(ask "Panel directory" "${PANEL_DIR}")"
  if [[ -z "${PANEL_DIR}" ]]; then
    die "Panel directory cannot be empty."
  fi
}

prompt_docker_options() {
  local scheme
  if [[ -z "${PANEL_DOMAIN}" ]]; then
    PANEL_DOMAIN="$(default_panel_domain)"
  fi
  while true; do
    PANEL_DOMAIN="$(ask "Preferred IP or domain name" "${PANEL_DOMAIN}")"
    PANEL_HTTPS="$(ask_yes_no "Use HTTPS" "${PANEL_HTTPS}")"
    if [[ "${PANEL_HTTPS}" == "1" ]] && is_ip_address "${PANEL_DOMAIN}"; then
      printf 'error: The Docker image obtains a certificate only for a hostname. Enter a hostname, or answer no to HTTPS.\n' >&2
      PANEL_HTTPS=0
      continue
    fi
    break
  done
  scheme="http"
  if [[ "${PANEL_HTTPS}" == "1" ]]; then
    scheme="https"
  fi
  APP_URL="${scheme}://${PANEL_DOMAIN}"
  ADMIN_EMAIL="$(ask_email "Admin email (Let's Encrypt uses this when HTTPS is on)" "${ADMIN_EMAIL:-}")"
  DOCKER_DIR="$(ask "Docker compose directory" "${DOCKER_DIR}")"
}

prompt_docker_proxy_options() {
  local default_url
  default_url="${APP_URL:-http://$(default_panel_domain)}"
  while true; do
    APP_URL="$(ask "Public panel URL" "${default_url}")"
    if [[ "${APP_URL}" == http://* || "${APP_URL}" == https://* ]]; then
      break
    fi
    printf 'Start the URL with http:// or https://.\n' >&2
  done
  if [[ "${APP_URL}" == https://* ]]; then
    PANEL_HTTPS=1
  else
    PANEL_HTTPS=0
  fi
  PANEL_DOMAIN="${APP_URL#http://}"
  PANEL_DOMAIN="${PANEL_DOMAIN#https://}"
  PANEL_DOMAIN="${PANEL_DOMAIN%%/*}"
  PANEL_DOMAIN="${PANEL_DOMAIN%%:*}"
  while true; do
    DOCKER_UPSTREAM_IP="$(ask "Reverse proxy IP" "${DOCKER_UPSTREAM_IP:-}")"
    if is_ip_address "${DOCKER_UPSTREAM_IP}"; then
      break
    fi
    printf 'Enter the reverse proxy IPv4 address. The Docker docs put this in trusted_proxies.\n' >&2
  done
  ADMIN_EMAIL="$(ask_email "Admin email" "${ADMIN_EMAIL:-}")"
  DOCKER_DIR="$(ask "Docker compose directory" "${DOCKER_DIR}")"
}

prompt_wings_options() {
  local certbot_default wings_default
  confirm_wings_host
  certbot_default="${PANEL_CERTBOT:-0}"
  if [[ -z "${PANEL_CERTBOT:-}" && "${INSTALL_MODE}" == "both" && "${PANEL_HTTPS}" == "1" ]] && ! is_ip_address "${PANEL_DOMAIN}"; then
    certbot_default=1
  fi
  PANEL_CERTBOT="$(ask_yes_no "Create a Let's Encrypt certificate for Wings with Certbot" "${certbot_default}")"
  if [[ "${PANEL_CERTBOT}" == "1" ]]; then
    wings_default="${WINGS_DOMAIN:-}"
    if [[ -z "${wings_default}" && "${INSTALL_MODE}" == "both" ]] && ! is_ip_address "${PANEL_DOMAIN}"; then
      wings_default="${PANEL_DOMAIN}"
    fi
    while true; do
      WINGS_DOMAIN="$(ask "Wings hostname for the certificate" "${wings_default}")"
      if [[ -z "${WINGS_DOMAIN}" ]]; then
        printf 'A hostname is required.\n' >&2
        continue
      fi
      if is_ip_address "${WINGS_DOMAIN}"; then
        printf 'error: Certbot standalone needs a hostname. An IP cannot get a certificate.\n' >&2
        continue
      fi
      break
    done
    CERTBOT_EMAIL="$(ask_email "Email for Let's Encrypt" "${CERTBOT_EMAIL:-${ADMIN_EMAIL:-}}")"
    export WINGS_DOMAIN CERTBOT_EMAIL
  elif [[ "${INSTALL_MODE}" == "both" && "${PANEL_HTTPS}" == "1" ]]; then
    log "The Wings docs say Wings must use SSL when the panel uses SSL."
  fi
}

# On a terminal, ask for every install choice. Environment values are the
# suggested answers. Dry-run does not ask. There is no silent install.
prompt_install_options() {
  local proceed
  INSTALL_MODE="${INSTALL_MODE:-panel}"
  PANEL_FIREWALL="${PANEL_FIREWALL:-0}"
  PANEL_WEBSERVER="${PANEL_WEBSERVER:-caddy}"
  DOCKER_DIR="${DOCKER_DIR:-/opt/pelican}"

  if [[ "${INSTALL_DRY_RUN:-0}" == "1" ]]; then
    PANEL_CERTBOT="${PANEL_CERTBOT:-0}"
    export INSTALL_MODE PANEL_FIREWALL PANEL_CERTBOT PANEL_WEBSERVER DOCKER_DIR
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "Run install.sh from a terminal. It asks what to install, then the options for that choice."
  fi

  INSTALL_MODE="$(ui_menu "What do you want to install?" "${INSTALL_MODE}" \
    "panel|Panel on this machine (PHP-FPM)" \
    "wings|Wings on this machine" \
    "both|Panel and Wings on this machine" \
    "docker|Panel in Docker (official compose, SQLite)" \
    "docker-proxy|Panel in Docker behind a reverse proxy")"

  case "${INSTALL_MODE}" in
    panel|both) prompt_panel_options ;;
    docker) prompt_docker_options ;;
    docker-proxy) prompt_docker_proxy_options ;;
    wings) ;;
    *) die "Unknown install mode ${INSTALL_MODE}." ;;
  esac

  if [[ "${INSTALL_MODE}" == "wings" || "${INSTALL_MODE}" == "both" ]]; then
    prompt_wings_options
  else
    PANEL_CERTBOT=0
  fi

  PANEL_FIREWALL="$(ask_yes_no "Configure the UFW firewall" "${PANEL_FIREWALL}")"

  log "Mode: ${INSTALL_MODE}"
  if [[ -n "${PANEL_DOMAIN:-}" ]]; then
    log "Domain: ${PANEL_DOMAIN}"
  fi
  if [[ -n "${APP_URL:-}" ]]; then
    log "Panel URL: ${APP_URL}"
  fi
  if [[ "${INSTALL_MODE}" == "panel" || "${INSTALL_MODE}" == "both" ]]; then
    log "Web server: ${PANEL_WEBSERVER}"
    if [[ "${PANEL_HTTPS}" == "1" && "${PANEL_WEBSERVER}" == "nginx" ]]; then
      log "HTTPS: yes (Certbot, then the documented Nginx SSL site)"
    elif [[ "${PANEL_HTTPS}" == "1" ]]; then
      log "HTTPS: yes (Caddy obtains the panel certificate)"
    else
      log "HTTPS: no"
    fi
    log "PHP: ${PHP_VERSION}"
    log "Database: ${PANEL_DATABASE}"
    if [[ "${PANEL_REDIS}" == "1" ]]; then
      log "Redis: yes"
    else
      log "Redis: no"
    fi
    log "Panel directory: ${PANEL_DIR}"
  fi
  if [[ "${INSTALL_MODE}" == "docker" || "${INSTALL_MODE}" == "docker-proxy" ]]; then
    log "Admin email: ${ADMIN_EMAIL}"
    log "Compose directory: ${DOCKER_DIR}"
    if [[ "${INSTALL_MODE}" == "docker-proxy" ]]; then
      log "Reverse proxy IP: ${DOCKER_UPSTREAM_IP}"
    fi
  fi
  if [[ "${PANEL_CERTBOT}" == "1" ]]; then
    log "Wings certificate: ${WINGS_DOMAIN}"
  elif [[ "${INSTALL_MODE}" == "wings" || "${INSTALL_MODE}" == "both" ]]; then
    log "Wings certificate: no"
  fi
  if [[ "${PANEL_FIREWALL}" == "1" ]]; then
    log "Firewall: UFW"
  else
    log "Firewall: no"
  fi

  proceed="$(ask_yes_no "Proceed with installation" "1")"
  if [[ "${proceed}" != "1" ]]; then
    die "Installation aborted."
  fi

  APP_URL="${APP_URL:-}"
  ADMIN_EMAIL="${ADMIN_EMAIL:-}"
  DOCKER_UPSTREAM_IP="${DOCKER_UPSTREAM_IP:-}"
  WINGS_DOMAIN="${WINGS_DOMAIN:-}"
  CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
  export INSTALL_MODE PANEL_DOMAIN PANEL_HTTPS PANEL_WEBSERVER PHP_VERSION PANEL_DATABASE PANEL_REDIS PANEL_DIR
  export PANEL_FIREWALL PANEL_CERTBOT DOCKER_DIR APP_URL ADMIN_EMAIL DOCKER_UPSTREAM_IP
  export WINGS_DOMAIN CERTBOT_EMAIL
}
