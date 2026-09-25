# Pelican installer

Installs Pelican on Ubuntu 24.04. `install.sh` asks what to install, then calls one script per stage. The questions live in `lib/ui.sh` and `lib/prompts.sh`, and the prompts are [Gum](https://github.com/charmbracelet/gum).

The commands follow the panel docs (Getting Started, the Nginx and Caddy tabs of Webserver Configuration, and Panel Setup), the Wings install page, the SSL guide, and the panel Docker page.

The docs do not include a Caddy package install. `scripts/install-caddy.sh` uses Caddy’s Debian/Ubuntu package instructions, then `scripts/configure-caddy.sh` writes the Caddyfile from the Pelican docs. Nginx is the Ubuntu package. Its HTTPS site is written after Certbot, because that file points at `/etc/letsencrypt` and Nginx will not start without those files.

## Run

On the Ubuntu machine:

```sh
curl -fsSL https://github.com/Kylewhite192/panel-onboard/archive/refs/heads/main.tar.gz | tar -xz -C /tmp
sudo bash /tmp/panel-onboard-main/install.sh
```

That downloads every script, then starts the installer. `install.sh` reads `scripts/` and `lib/` beside it, so curling `install.sh` on its own has nothing to run.

From a checkout of this repository:

```sh
sudo bash install.sh
```

`bash` is the way to start it. A zip of these scripts can store them without the executable bit, and `./install.sh` then stops at the first stage.

The installer installs Gum from Charm's Ubuntu repository when `gum` is not already on the machine. Lists are menus: the suggestion starts highlighted, and Enter selects it. A text field starts filled with the suggestion, and Enter keeps it. Yes or No starts on the suggested answer. Escape or Ctrl+C stops the installer.

The first question is what to install:

1. Panel on this machine (PHP-FPM). Caddy or Nginx is the next question.
2. Wings on this machine.
3. Panel and Wings on this machine.
4. Panel in Docker, using the official compose file (SQLite until the web installer says otherwise).
5. Panel in Docker behind a reverse proxy, using the compose file and Caddyfile from that same page.

Panel choices:

- Preferred IP or domain name. The suggestion is this machine's first IPv4 address, or `127.0.0.1` when that is the only one. An IP is allowed only for HTTP.
- HTTPS, default no. Caddy obtains the panel certificate. Nginx asks for an email and uses Certbot, then the documented SSL site.
- Web server, default Caddy. Also Nginx.
- PHP version, default 8.5 (also 8.4 or 8.3).
- Database, default sqlite. MariaDB asks for the `pelican` user's password.
- Redis, default no.
- Panel directory, default `/var/www/pelican`.

It then installs the panel and runs `php artisan p:environment:setup`. That command copies `.env`, generates `APP_KEY`, and does not ask for a URL. The installer sets `APP_URL` to the address you chose so the installer page does not load assets from `panel.test`. Back up `APP_KEY` from `/var/www/pelican/.env`, then open `/installer` in a browser.

When that page has finished, run `sudo bash scripts/post-install.sh`. It creates the `pelican-queue` service and the `www-data` cron that runs `schedule:run` every minute, which is what the troubleshooting page expects. It refuses to run until `.env` contains `APP_INSTALLED=true`. The Docker image has its own queue worker, so this script is only for the panel on the host.

MariaDB and Redis settings are entered again in the web installer. The installer does not run `p:environment:database` or `p:redis:setup`.

Wings choices, from the Wings install page:

- Docker CE from `https://get.docker.com/` on the stable channel.
- The Wings binary and the systemd unit. The service is not started. Wings needs `/etc/pelican/config.yml` from the panel node page, then `wings --debug`, then `systemctl enable --now wings`.
- Certbot, optional. Standalone HTTP challenge, plus the 23:00 renewal cron from the SSL guide. Suggested when the panel on this machine is using HTTPS.
- OpenVZ and LXC ask before continuing. The modified `-grs-ipv6-64` and `-mod-std-ipv6-64` kernels are refused.

Docker choices:

- Public URL, or an IP with HTTP. `ADMIN_EMAIL` is required. HTTPS on a hostname is what the image uses for Let's Encrypt.
- Compose directory, default `/opt/pelican`.
- Reverse proxy mode asks for the proxy's IPv4 address and writes it into `trusted_proxies`.

Every mode can configure UFW. SSH is allowed on the port of this session and on the ports `sshd` is using. If neither is known, the rule is `22/tcp`. Panel or Docker also allow `80/tcp` and `443/tcp`, and Wings allows `8080/tcp` and `2022/tcp`. Game allocation ports are left closed until you add them.

Environment variables pre-fill the suggestions: `INSTALL_MODE`, `PANEL_DOMAIN`, `PANEL_HTTPS`, `PANEL_WEBSERVER`, `PHP_VERSION`, `PANEL_DATABASE`, `PANEL_DB_PASSWORD`, `PANEL_REDIS`, `PANEL_DIR`, `PANEL_FIREWALL`, `PANEL_CERTBOT`, `WINGS_DOMAIN`, `CERTBOT_EMAIL`, `APP_URL`, `ADMIN_EMAIL`, `DOCKER_DIR`, `DOCKER_UPSTREAM_IP`.

`INSTALL_DRY_RUN=1 bash install.sh` prints the script order and does not ask questions or change the system. `INSTALL_MODE` selects which order is printed (`panel` when unset).

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/check-os.sh` | Requires Ubuntu 24.04 |
| `scripts/install-php.sh` | PHP 8.5 (or 8.4/8.3) and the extensions from the docs, via `ppa:ondrej/php` |
| `scripts/install-caddy.sh` | Installs the Caddy package. Stops Nginx if it is running |
| `scripts/download-panel.sh` | Downloads the latest panel tarball into `/var/www/pelican`. Asks before unpacking over an existing panel |
| `scripts/install-composer.sh` | Installs Composer and runs `composer install` |
| `scripts/configure-caddy.sh` | Writes the HTTP or HTTPS Caddyfile and restarts Caddy |
| `scripts/install-nginx.sh` | Installs Nginx and removes the default site. Stops Caddy if it is running |
| `scripts/configure-nginx.sh` | Writes the documented Nginx site. HTTPS runs Certbot first |
| `scripts/install-mariadb.sh` | Optional. MariaDB, database `panel`, user `pelican` |
| `scripts/install-redis.sh` | Optional. Redis from packages.redis.io |
| `scripts/set-permissions.sh` | `chmod` storage and cache, `chown` the tree to `www-data` |
| `scripts/panel-setup.sh` | Panel mode. Runs `php artisan p:environment:setup`, then permissions |
| `scripts/install-docker-engine.sh` | Docker CE, stable channel, for Wings and for the panel image |
| `scripts/install-wings.sh` | Wings binary and systemd unit. Does not start Wings |
| `scripts/install-certbot.sh` | Optional. Certbot standalone certificate for Wings, and the renewal cron |
| `scripts/configure-firewall.sh` | Optional. UFW rules for the selected mode, including the SSH port in use |
| `scripts/install-panel-docker.sh` | Official `compose.yml`, or that file plus the reverse-proxy Caddyfile. Picks another `172.20`–`172.31` subnet when `172.20.0.0/16` is taken |
| `scripts/post-install.sh` | After the browser installer. Queue worker and the panel schedule cron |

Apache is not part of this installer. The queue worker and the panel cron are in `scripts/post-install.sh`, which runs after `/installer`, not as a stage of `install.sh`. The panel Docker guide still calls the non-Docker install the one to prefer.
