#!/usr/bin/env bash
# Stage: Webserver Configuration (Nginx tab) and Enabling Configuration
# https://pelican.dev/docs/panel/webserver-config
#
# HTTPS writes the documented SSL site. That file references
# /etc/letsencrypt/live/<domain>/, and the page says the web server will not
# start until those files exist. This script therefore starts the documented
# HTTP site, runs the SSL guide's `certbot certonly --nginx -d <domain>`,
# then replaces the site with the SSL file.
#
# Ubuntu 24.04 ships Nginx 1.24. The current docs enable HTTP/2 with
# `http2 on;`, which Nginx 1.25.1 added. 1.24 uses `listen 443 ssl http2`.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ -z "${PANEL_DOMAIN}" ]]; then
  die "Set PANEL_DOMAIN to the hostname (or IP, for HTTP) used in the Nginx site."
fi

reject_ip_with_https

socket="$(nginx_fpm_socket)"
available="/etc/nginx/sites-available/pelican.conf"
enabled="/etc/nginx/sites-enabled/pelican.conf"

write_http_site() {
  cat >"${available}" <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};

    root ${PANEL_DIR}/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pelican.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \\.php\$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        fastcgi_pass ${socket};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \\n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF
}

write_ssl_site() {
  cat >"${available}" <<EOF
server_tokens off;

server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${PANEL_DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pelican.app-access.log;
    error_log  /var/log/nginx/pelican.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    ssl_certificate /etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        fastcgi_pass ${socket};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \\n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF
}

enable_site() {
  ln -sfn "${available}" "${enabled}"
  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

log "Writing the Nginx HTTP site."
write_http_site
enable_site

if [[ "${PANEL_HTTPS}" != "1" ]]; then
  log "Nginx is serving ${PANEL_DOMAIN} with HTTP."
  exit 0
fi

if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
  die "Nginx HTTPS needs CERTBOT_EMAIL."
fi

export DEBIAN_FRONTEND=noninteractive
log "Installing Certbot's Nginx plugin."
apt-get update
apt-get install -y python3-certbot-nginx

log "Requesting a certificate for ${PANEL_DOMAIN}."
certbot certonly --nginx --non-interactive --agree-tos \
  --email "${CERTBOT_EMAIL}" -d "${PANEL_DOMAIN}" --keep-until-expiring

log "Replacing the site with the documented SSL configuration."
write_ssl_site
enable_site

cron_line='0 23 * * * certbot renew --quiet --deploy-hook "systemctl restart nginx"'
current="$(crontab -l 2>/dev/null || true)"
if [[ "${current}" != *"systemctl restart nginx"* ]]; then
  printf '%s\n%s\n' "${current}" "${cron_line}" | sed '/^$/d' | crontab -
  log "Installed the 23:00 renewal cron from the SSL guide."
else
  log "A certbot renew cron entry for Nginx is already installed."
fi

log "Nginx is serving https://${PANEL_DOMAIN}/"
