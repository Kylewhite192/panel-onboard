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

# Inclusive start and end of an IPv4 CIDR, as integers.
cidr_bounds() {
  local cidr="$1" prefix base mask start end
  [[ "${cidr}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)(/([0-9]+))?$ ]] || return 1
  prefix="${BASH_REMATCH[6]:-32}"
  (( prefix >= 0 && prefix <= 32 )) || return 1
  (( 10#${BASH_REMATCH[1]} <= 255 && 10#${BASH_REMATCH[2]} <= 255 && 10#${BASH_REMATCH[3]} <= 255 && 10#${BASH_REMATCH[4]} <= 255 )) || return 1
  base=$(( (10#${BASH_REMATCH[1]} << 24) + (10#${BASH_REMATCH[2]} << 16) + (10#${BASH_REMATCH[3]} << 8) + 10#${BASH_REMATCH[4]} ))
  if (( prefix == 0 )); then
    printf '0 4294967295\n'
    return 0
  fi
  mask=$(( (4294967295 << (32 - prefix)) & 4294967295 ))
  start=$(( base & mask ))
  end=$(( start | (mask ^ 4294967295) ))
  printf '%s %s\n' "${start}" "${end}"
}

cidrs_overlap() {
  local a1 a2 b1 b2
  read -r a1 a2 < <(cidr_bounds "$1") || return 1
  read -r b1 b2 < <(cidr_bounds "$2") || return 1
  (( a1 <= b2 && b1 <= a2 ))
}

# The docs use 172.20.0.0/16. A host or Docker network that overlaps that
# range makes compose up fail, including a wider route such as 172.16.0.0/12.
# Pick the next free 172.20–172.31/16.
choose_compose_subnet() {
  local -a cidrs=()
  local n cidr existing line taken
  while read -r line; do
    [[ "${line}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+$ ]] || continue
    cidrs+=("${line}")
  done < <(
    ip -4 addr show 2>/dev/null | awk '/inet / { print $2 }'
    ip -4 route show 2>/dev/null | awk '$1 ~ /\// { print $1 }'
    docker network ls -q 2>/dev/null | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null || true
  )
  for n in $(seq 20 31); do
    cidr="172.${n}.0.0/16"
    taken=0
    if ((${#cidrs[@]} > 0)); then
      for existing in "${cidrs[@]}"; do
        if cidrs_overlap "${cidr}" "${existing}"; then
          taken=1
          break
        fi
      done
    fi
    if (( taken == 0 )); then
      printf '%s' "${cidr}"
      return 0
    fi
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
  key_line="$(docker compose logs panel 2>/dev/null | grep 'Generated app key:' | tail -n 1 || true)"
  if [[ -n "${key_line}" ]]; then
    secrets_save_app_key "${key_line##*Generated app key: }"
    log "Back up that app key from ${INSTALLER_SECRETS} and store it off this server."
  else
    log "If this is the first start, copy the app key into ${INSTALLER_SECRETS}. The container log has it; this installer log does not."
  fi
)
log "Finish in the browser at ${APP_URL}/installer"
log "The first start applies migrations. The panel stays unavailable until that finishes."
