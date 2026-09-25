# Pelican Panel installer

Installs the Pelican Panel on Ubuntu 24.04 with PHP-FPM and Caddy. `install.sh` calls one script per stage. The commands follow the panel docs (Getting Started, the Caddy tab of Webserver Configuration, and Panel Setup).

The docs do not include a Caddy package install. `scripts/install-caddy.sh` uses Caddy’s Debian/Ubuntu package instructions, then `scripts/configure-caddy.sh` writes the Caddyfile from the Pelican docs.

## Run

```sh
sudo PANEL_DOMAIN=panel.example.com ./install.sh
```

HTTP is the default, so an IP address is allowed as `PANEL_DOMAIN`. For the documented HTTPS Caddyfile:

```sh
sudo PANEL_DOMAIN=panel.example.com PANEL_HTTPS=1 ./install.sh
```

MariaDB instead of SQLite, and Redis, are optional. The docs say to enter both in the web installer, and not to run `p:environment:database` or `p:redis:setup` on a first install.

```sh
sudo PANEL_DOMAIN=panel.example.com \
  PANEL_DATABASE=mariadb \
  PANEL_DB_PASSWORD='choose-a-password' \
  PANEL_REDIS=1 \
  ./install.sh
```

After `install.sh` finishes, run the interactive environment setup and back up `APP_KEY` from `/var/www/pelican/.env`:

```sh
sudo ./scripts/panel-setup.sh
```

Then open `http://panel.example.com/installer` (or `https://` when `PANEL_HTTPS=1`).

`INSTALL_DRY_RUN=1 ./install.sh` prints the script order and does not change the system.

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/check-os.sh` | Requires Ubuntu 24.04 |
| `scripts/install-php.sh` | PHP 8.5 (or 8.4/8.3) and the extensions from the docs, via `ppa:ondrej/php` |
| `scripts/install-caddy.sh` | Installs the Caddy package |
| `scripts/download-panel.sh` | Downloads the latest panel tarball into `/var/www/pelican` |
| `scripts/install-composer.sh` | Installs Composer and runs `composer install` |
| `scripts/configure-caddy.sh` | Writes the HTTP or HTTPS Caddyfile and restarts Caddy |
| `scripts/install-mariadb.sh` | Optional. MariaDB, database `panel`, user `pelican` |
| `scripts/install-redis.sh` | Optional. Redis from packages.redis.io |
| `scripts/set-permissions.sh` | `chmod` storage and cache, `chown` the tree to `www-data` |
| `scripts/panel-setup.sh` | Interactive `php artisan p:environment:setup`, then permissions again |

Nginx, Apache, Certbot, the queue worker, and Wings are not part of this installer.
