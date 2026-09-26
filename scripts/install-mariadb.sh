#!/usr/bin/env bash
# Stages: Install MariaDB, Create User & Database
# https://pelican.dev/docs/panel/advanced/mysql
#
# Only for PANEL_DATABASE=mariadb. The docs say not to run
# php artisan p:environment:database on a first install; enter the database in
# the web installer.
#
# The documented login is `mysql -u root -p`, and the page says the root
# password is often empty. This script connects as root over the local socket.

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
dry_run_step

if [[ -z "${PANEL_DB_PASSWORD:-}" ]]; then
  die "Set PANEL_DB_PASSWORD for the pelican database user."
fi

log "Installing MariaDB."
curl --proto '=https' --tlsv1.2 -fsSL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
apt-get install -y mariadb-server
systemctl enable --now mariadb

sql_password="$(sql_escape "${PANEL_DB_PASSWORD}")"

log "Creating database panel and user pelican@127.0.0.1."
# ALTER USER runs even when the account already exists, so a second install
# replaces the password. CREATE USER IF NOT EXISTS alone would leave the old one.
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pelican'@'127.0.0.1';
ALTER USER 'pelican'@'127.0.0.1' IDENTIFIED BY '${sql_password}';
GRANT ALL PRIVILEGES ON panel.* TO 'pelican'@'127.0.0.1';
SQL
