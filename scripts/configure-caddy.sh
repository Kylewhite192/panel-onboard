#!/usr/bin/env bash
# Stage: Webserver Configuration (Caddy tab) and Enabling Configuration
# https://pelican.dev/docs/panel/webserver-config
#
# HTTPS uses the documented Caddyfile. That file does not point at Certbot
# paths; Caddy requests the certificate itself. The page-level warning about
# creating certificates first is written for configs that reference
# /etc/letsencrypt. Nginx and Apache are not configured here.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ -z "${PANEL_DOMAIN}" ]]; then
  die "Set PANEL_DOMAIN to the hostname (or IP, for HTTP) used in the Caddyfile."
fi

reject_ip_with_https

socket="$(php_fpm_socket)"
caddyfile="/etc/caddy/Caddyfile"

log "Replacing ${caddyfile}."
rm -f "${caddyfile}"
install -d /var/log/caddy

if [[ "${PANEL_HTTPS}" == "1" ]]; then
  cat >"${caddyfile}" <<EOF
{
    servers :443 {
        timeouts {
            read_body 120s
        }
    }
}

${PANEL_DOMAIN} {
    root * ${PANEL_DIR}/public

    file_server

    php_fastcgi ${socket} {
        root ${PANEL_DIR}/public
        index index.php

        env PHP_VALUE "upload_max_filesize = 100M
        post_max_size = 100M"
        env HTTP_PROXY ""
        env HTTPS "on"

        read_timeout 300s
        dial_timeout 300s
        write_timeout 300s
    }

    header Strict-Transport-Security "max-age=16768000; preload;"
    header X-Content-Type-Options "nosniff"
    header X-XSS-Protection "1; mode=block;"
    header X-Robots-Tag "none"
    header Content-Security-Policy "frame-ancestors 'self'"
    header X-Frame-Options "DENY"
    header Referrer-Policy "same-origin"

    request_body {
        max_size 100m
    }

    respond /.ht* 403

    log {
        output file /var/log/caddy/pelican.log {
            roll_size 100MiB
            roll_keep_for 7d
        }
        level INFO
    }
}
EOF
else
  cat >"${caddyfile}" <<EOF
{
    servers :80 {
        timeouts {
            read_body 120s
        }
    }
}

${PANEL_DOMAIN}:80 {
    root * ${PANEL_DIR}/public

    file_server

    php_fastcgi ${socket} {
        root ${PANEL_DIR}/public
        index index.php

        env PHP_VALUE "upload_max_filesize = 100M
        post_max_size = 100M"
        env HTTP_PROXY ""

        read_timeout 300s
        dial_timeout 300s
        write_timeout 300s
    }

    header Strict-Transport-Security "max-age=16768000; preload;"
    header X-Content-Type-Options "nosniff"
    header X-XSS-Protection "1; mode=block;"
    header X-Robots-Tag "none"
    header Content-Security-Policy "frame-ancestors 'self'"
    header X-Frame-Options "DENY"
    header Referrer-Policy "same-origin"

    request_body {
        max_size 100m
    }

    respond /.ht* 403

    log {
        output file /var/log/caddy/pelican.log {
            roll_size 100MiB
            roll_keep_for 7d
        }
        level INFO
    }
}
EOF
fi

log "Restarting Caddy."
systemctl restart caddy
