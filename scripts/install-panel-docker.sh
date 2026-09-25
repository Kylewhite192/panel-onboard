#!/usr/bin/env bash
# Panel Docker compose.
# https://pelican.dev/docs/panel/advanced/docker
#
# docker writes the documented compose.yml and runs docker compose up -d.
# docker-proxy also bind-mounts the documented reverse-proxy Caddyfile.
# The image uses SQLite until the web installer is pointed at another database.
# The docs still recommend the standard (non-Docker) install.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ -z "${APP_URL:-}" || -z "${ADMIN_EMAIL:-}" || -z "${DOCKER_DIR:-}" ]]; then
  die "Docker install needs APP_URL, ADMIN_EMAIL, and DOCKER_DIR."
fi
if [[ "${APP_URL}" != http://* && "${APP_URL}" != https://* ]]; then
  die "APP_URL must start with http:// or https://."
fi
case "${DOCKER_DIR}" in
  /*) ;;
  *) die "DOCKER_DIR must be an absolute path." ;;
esac

log "The panel Docker guide is still a work in progress. The standard install is the Caddy path."

# The docs use 172.20.0.0/16. A host or Docker network in that range makes
# compose up fail, so pick the next free 172.20–172.31/16.
choose_compose_subnet() {
  local n prefix cidr existing
  for n in $(seq 20 31); do
    prefix="172.${n}"
    cidr="${prefix}.0.0/16"
    if ip -4 addr show 2>/dev/null | grep -q "inet ${prefix}\\."; then
      continue
    fi
    if ip -4 route show 2>/dev/null | grep -Eq "(^| )${prefix}\\."; then
      continue
    fi
    existing="$(docker network ls -q 2>/dev/null | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null || true)"
    if printf '%s\n' "${existing}" | grep -q "^${prefix}\\."; then
      continue
    fi
    printf '%s' "${cidr}"
    return 0
  done
  return 1
}

compose_subnet="$(choose_compose_subnet)" || die "Every 172.20–172.31/16 range is already in use."
if [[ "${compose_subnet}" != "172.20.0.0/16" ]]; then
  log "172.20.0.0/16 overlaps an existing network. Using ${compose_subnet} for the panel compose network."
fi

install -d "${DOCKER_DIR}"

if [[ "${INSTALL_MODE}" == "docker-proxy" ]]; then
  if [[ -z "${DOCKER_UPSTREAM_IP:-}" ]]; then
    die "Reverse proxy mode needs DOCKER_UPSTREAM_IP."
  fi
  log "Writing ${DOCKER_DIR}/Caddyfile for a reverse proxy at ${DOCKER_UPSTREAM_IP}."
  cat >"${DOCKER_DIR}/Caddyfile" <<EOF
{
    admin off
    servers {
        trusted_proxies static ${DOCKER_UPSTREAM_IP}
    }
}

:80 {
    root * /var/www/html/public
    encode gzip

    php_fastcgi 127.0.0.1:9000
    file_server
}
EOF
fi

log "Writing ${DOCKER_DIR}/compose.yml."
if [[ "${INSTALL_MODE}" == "docker-proxy" ]]; then
  caddy_volume="      - ./Caddyfile:/etc/caddy/Caddyfile"
else
  caddy_volume=""
fi

cat >"${DOCKER_DIR}/compose.yml" <<EOF
services:
  panel:
    image: ghcr.io/pelican/panel:latest
    restart: always
    networks:
      - default
    ports:
      - "80:80"
      - "443:443"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - pelican-data:/pelican-data
      - pelican-logs:/var/www/html/storage/logs
${caddy_volume}
    environment:
      XDG_DATA_HOME: /pelican-data
      APP_URL: "${APP_URL}"
      ADMIN_EMAIL: "${ADMIN_EMAIL}"

volumes:
  pelican-data:
  pelican-logs:

networks:
  default:
    ipam:
      config:
        - subnet: ${compose_subnet}
EOF

log "Starting the panel container."
(
  cd "${DOCKER_DIR}"
  docker compose up -d
  key_line="$(docker compose logs panel 2>/dev/null | grep 'Generated app key:' || true)"
  if [[ -n "${key_line}" ]]; then
    log "${key_line}"
    log "Back up that app key off this server."
  else
    log "If this is the first start, back up the app key with: docker compose logs panel | grep 'Generated app key:'"
  fi
)
log "Finish in the browser at ${APP_URL}/installer"
log "The first start applies migrations. The panel stays unavailable until that finishes."
