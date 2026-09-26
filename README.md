# Pelican installer

Installs [Pelican](https://pelican.dev) on Ubuntu 24.04. The commands follow the panel docs (Getting Started, the Nginx and Caddy tabs of Webserver Configuration, and Panel Setup), the Wings install page, the SSL guide, and the panel Docker page.

Installer version: `0.1.0-alpha`.

## Supported system

Ubuntu 24.04 with systemd as PID 1. Other Debian releases, Rocky, and Alma are not supported.

An imported WSL distro does not start systemd until `/etc/wsl.conf` says so. The installer writes `systemd=true` there and stops. Close the session, and from Windows run `wsl --terminate <distro-name>`, then start the distro and run the installer again.

## Install

From the `v0.1.0-alpha` tag:

```sh
curl -fsSL https://github.com/Kylewhite192/panel-onboard/archive/refs/tags/v0.1.0-alpha.tar.gz | tar -xz -C /tmp
sudo bash /tmp/panel-onboard-0.1.0-alpha/install.sh
```

`main` keeps moving. Use the tag above for a known installer. `install.sh` reads `scripts/` and `lib/` beside it, so curling `install.sh` on its own has nothing to run.

From a checkout:

```sh
sudo bash install.sh
```

`bash` is the way to start it. A zip of these scripts can store them without the executable bit, and `./install.sh` then stops at the first stage.

`INSTALL_DRY_RUN=1 bash install.sh` prints the script order and does not ask questions or change the system. `INSTALL_MODE` selects which order is printed (`panel` when unset).

## What each mode does

The questions use [Gum](https://github.com/charmbracelet/gum). The installer installs it from Charm's Ubuntu repository when it is missing. Lists are menus. A text field starts filled with the suggestion. Yes or No starts on the suggested answer. Escape or Ctrl+C stops the installer.

1. Panel on this machine (PHP-FPM). Caddy or Nginx is the next question.
2. Wings on this machine.
3. Panel and Wings on this machine.
4. Panel in Docker, using the official compose file (SQLite until the web installer says otherwise).
5. Panel in Docker behind a reverse proxy, using the compose file and Caddyfile from that same page.

Panel choices: address (an IP is allowed only for HTTP), HTTPS (default no), web server (default Caddy), PHP (default 8.5, also 8.4 or 8.3), database (default sqlite), Redis (default no), and the panel directory (default `/var/www/pelican`).

The panel install runs `php artisan p:environment:setup`. That copies `.env` and generates `APP_KEY`. It does not ask for a URL. The installer sets `APP_URL` so the installer page does not load assets from `panel.test`. MariaDB and Redis settings are entered again in the browser. The installer does not run `p:environment:database` or `p:redis:setup`.

Wings installs Docker CE from `https://get.docker.com/` on the stable channel, then the Wings binary and the systemd unit. The service is not started. Wings needs `/etc/pelican/config.yml` from the panel node page, then `wings --debug`, then `systemctl enable --now wings`. OpenVZ and LXC ask before continuing. The modified `-grs-ipv6-64` and `-mod-std-ipv6-64` kernels are refused. Certbot is optional: a standalone HTTP challenge, plus the 23:00 renewal cron from the SSL guide. Renewal stops Caddy or Nginx if either is listening on port 80, then starts it again. Wings is restarted only when it is already running, so the first certificate does not start it.

Docker mode asks for a public URL or an IP with HTTP, and for `ADMIN_EMAIL`. HTTPS on a hostname is what the image uses for Let's Encrypt. The compose directory defaults to `/opt/pelican`. Reverse proxy mode asks for the proxy's IPv4 address and writes it into `trusted_proxies`. The first container start applies migrations, so the panel stays down until that finishes. The image tag is `ghcr.io/pelican/panel:latest`; the installer records the image digest when Docker reports one.

Every mode can configure UFW. SSH is allowed on the port of this session and on the ports `sshd` is using. If neither is known, the rule is `22/tcp`. Panel or Docker also allow `80/tcp` and `443/tcp`, and Wings allows `8080/tcp` and `2022/tcp`. Game allocation ports are left closed until you add them.

Environment variables pre-fill the suggestions: `INSTALL_MODE`, `PANEL_DOMAIN`, `PANEL_HTTPS`, `PANEL_WEBSERVER`, `PHP_VERSION`, `PANEL_DATABASE`, `PANEL_DB_PASSWORD`, `PANEL_REDIS`, `PANEL_DIR`, `PANEL_FIREWALL`, `PANEL_CERTBOT`, `WINGS_DOMAIN`, `CERTBOT_EMAIL`, `APP_URL`, `ADMIN_EMAIL`, `DOCKER_DIR`, `DOCKER_UPSTREAM_IP`.

## Files on the server

| Path | Mode | What it holds |
| --- | --- | --- |
| `/root/pelican-installer/state.env` | `600` | Choices and which stages finished |
| `/root/pelican-installer/secrets.env` | `600` | MariaDB password and `APP_KEY` |
| `/root/pelican-installer/install-summary.txt` | `600` | Verification checklist, including the panel and Wings release that was installed |
| `/var/log/pelican-installer.log` | `600` | Status lines and command output |

A generated MariaDB password is shown once on the terminal, because the browser installer asks for it again. It is not written to the log. `APP_KEY` is copied into `secrets.env` and is not written to the log.

The panel tarball and the Wings binary are checked against the SHA256 file published with that GitHub release. Composer’s installer is checked against the SHA384 signature at `https://getcomposer.org/installer.sig`. The Docker engine script and the MariaDB repository script do not publish a checksum this installer can pin.

## Resume

A stage is marked complete only after that script exits 0. Run the installer again after a failure and Gum offers:

- Resume installation. Saved choices are loaded, including a custom panel directory, and finished stages are skipped.
- View failure details. This prints the stage markers and the last lines of the log.
- Start again. Stage markers are cleared and the questions are asked again, with the previous answers filled in. `secrets.env` is kept.
- Exit.

If the saved installer version and the script you are running differ, the menu warns before resuming. Start again writes a dated boundary in the log.

A fatal error ends with the stage name, the log path, and a reminder that you can rerun to resume.

## After the browser installer

When `/installer` has finished, run:

```sh
sudo bash scripts/post-install.sh
```

It reads the saved panel directory, then creates the `pelican-queue` service and the `www-data` cron that runs `schedule:run` every minute. It refuses to run until `.env` contains `APP_INSTALLED=true`. The Docker image has its own queue worker, so this script is only for the panel on the host.

The installer’s health check accepts only HTTP 2xx or 3xx. It retries for about 30 seconds so a Docker panel can finish migrations. Wings counts as success when the binary and unit exist and the service is still stopped.

## Recovery

Rerun `sudo bash install.sh` and choose Resume. Stages already marked complete are skipped. A stage that failed is run again.

The log is `/var/log/pelican-installer.log`. Command output from package installs, downloads, Composer, and Docker is appended there. Lines that contain the database password or an application key are removed first. View failure details shows the end of that file.

`post-install.sh` uses the panel directory stored in `state.env`, so a directory other than `/var/www/pelican` still works in a new shell.

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/check-os.sh` | Requires Ubuntu 24.04 and systemd |
| `scripts/install-php.sh` | PHP 8.5 (or 8.4/8.3) and the extensions from the docs, via `ppa:ondrej/php` |
| `scripts/install-caddy.sh` | Installs the Caddy package. Stops Nginx if it is running |
| `scripts/download-panel.sh` | Downloads the latest panel tarball, checks its published SHA256, and records the release tag. Asks before unpacking over an existing panel |
| `scripts/install-composer.sh` | Checks Composer’s installer signature, then runs `composer install` |
| `scripts/configure-caddy.sh` | Writes the HTTP or HTTPS Caddyfile and restarts Caddy |
| `scripts/install-nginx.sh` | Installs Nginx and removes the default site. Stops Caddy if it is running |
| `scripts/configure-nginx.sh` | Writes the documented Nginx site. HTTPS runs Certbot first |
| `scripts/install-mariadb.sh` | Optional. MariaDB, database `panel`, user `pelican` |
| `scripts/install-redis.sh` | Optional. Redis from packages.redis.io |
| `scripts/set-permissions.sh` | `chmod` storage and cache, `chown` the tree to `www-data` |
| `scripts/panel-setup.sh` | Panel mode. Runs `php artisan p:environment:setup`, then permissions |
| `scripts/install-docker-engine.sh` | Docker CE, stable channel, for Wings and for the panel image |
| `scripts/install-wings.sh` | Wings binary, checked against the published SHA256, and the systemd unit. Does not start Wings |
| `scripts/install-certbot.sh` | Optional. Certbot standalone certificate for Wings, and the renewal cron |
| `scripts/configure-firewall.sh` | Optional. UFW rules for the selected mode, including the SSH port in use |
| `scripts/install-panel-docker.sh` | Official `compose.yml`, or that file plus the reverse-proxy Caddyfile. Picks another `172.20`–`172.31` subnet when that range overlaps an existing network, including a wider one such as `172.16.0.0/12` |
| `scripts/post-install.sh` | After the browser installer. Queue worker, the panel schedule cron, and a check that both are running |
| `scripts/verify-install.sh` | Checks the services for the mode that was installed. Wings is left stopped |

Apache is not part of this installer. The panel Docker guide still calls the non-Docker install the one to prefer.

Caddy’s package install is not in the Pelican docs. `scripts/install-caddy.sh` uses Caddy’s Debian/Ubuntu package instructions, then `scripts/configure-caddy.sh` writes the Caddyfile from the Pelican docs. Nginx is the Ubuntu package. Its HTTPS site is written after Certbot, because that file points at `/etc/letsencrypt` and Nginx will not start without those files.
