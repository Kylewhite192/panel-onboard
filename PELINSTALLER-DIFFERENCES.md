# Differences from Pelinstaller Production

Compared with `Pelinstaller-Production (2).zip` (Zinidia/Pelinstaller, Production). That project says it is not part of the official Pelican project. This installer follows the official panel docs: Getting Started, the Nginx and Caddy tabs, and Panel Setup.

The comparison below is their bare-metal panel script, `installers/panel.sh`, against `install.sh` and `scripts/` here. This installer now has its own menu for the panel, Wings, both, and two Docker layouts from the Pelican docs. It does not offer their Basic or uninstall modes.

## What each installer is for

| | Pelinstaller `panel` | This installer |
| --- | --- | --- |
| Web server | Nginx from the distro | Caddy by default, or Nginx from Ubuntu. The question is on the panel path |
| Operating systems | Ubuntu 20.04, 22.04, 24.04, 26.04; Debian 10 through 13; AlmaLinux and Rocky Linux 8 and 9 | Ubuntu 24.04 only |
| PHP | 8.5 only | 8.5, 8.4, or 8.3 |
| Database | MariaDB always | SQLite unless you choose MariaDB |
| Redis | Always | Only if you say yes |
| HTTPS | Certbot and the Nginx plugin, or an Nginx file that assumes a certificate already exists | Caddy obtains its own certificate. Nginx uses Certbot, then the documented SSL site |
| Firewall | Optional UFW or firewalld | Optional UFW. The SSH port in use (22 if unknown), plus 80 and 443, and for Wings 8080 and 2022 |
| Wings | Docker CE, Wings binary, systemd unit enabled and not started, optional MariaDB user for database hosts | Docker CE, Wings binary, systemd unit installed and not started. No database-host user |
| Docker | Pelinstaller's compose file: panel, MariaDB, and Redis, then an admin user | The official compose file (SQLite, web installer), or that file plus the reverse-proxy Caddyfile |
| Finish | Admin user, migrated database, cron, queue worker | Web installer at `/installer`. `scripts/post-install.sh` adds the queue worker and schedule cron after that. Wings still needs `config.yml` from the panel |

## Questions

Pelinstaller asks for a timezone, an email, an admin password, an FQDN or IP, a firewall, and Let's Encrypt. It prints a summary and asks you to confirm before it installs. The timezone is shown in that summary. `configure()` does not write it into `.env`.

This installer starts with a Gum menu, then asks for the options that mode needs: an IP or domain, HTTPS, the web server, PHP version, SQLite or MariaDB, Redis, the panel directory, Certbot for Wings, and UFW. Docker mode asks for the public URL, an admin email, and the compose directory. The web server, PHP version, and database are menus. A text field starts with the suggestion. It does not ask for an admin account. The web installer does that. Gum is installed from Charm's apt repository when it is missing.

## Install steps

| Step | Pelinstaller `panel.sh` | This installer |
| --- | --- | --- |
| Packages | `apt install` PHP 8.5 and extensions, `mariadb-server`, `nginx`, `redis-server`, `zip`, `unzip`, `tar`, `git`, `cron` | PHP and the documented extensions from `ppa:ondrej/php`. `curl`, `tar`, and `unzip`. Caddy separately |
| PHP repository | `ppa:ondrej/php` when that PPA has the Ubuntu release. Otherwise the distro's PHP packages | `ppa:ondrej/php` only. No fallback |
| PHP-FPM | Started with Nginx. On Alma and Rocky, a downloaded `www-pelican.conf` pool | `systemctl enable --now phpX.Y-fpm` |
| Panel files | Same `panel.tar.gz` URL. Creates a few cache directories, then `chmod` on `storage/*` and `bootstrap/cache/` before Composer | Same URL. Permissions run after setup |
| `.env` | `cp .env.example .env` | The panel's Composer script copies `.env.example` if `.env` is missing |
| Composer | `composer install --no-dev --optimize-autoloader` | Same command. `composer update` is not run |
| Web server file | `configs/nginx.conf` or `configs/nginx_ssl.conf`, with `<domain>` and `<php_socket>` replaced. Nginx site `pelican.conf`, then `systemctl restart nginx` | The documented Caddyfile, HTTP or HTTPS, then `systemctl restart caddy` |
| MariaDB | Distro package. Database `panel`, user `pelican@127.0.0.1`, generated 64-character password, `GRANT ALL ... WITH GRANT OPTION` | Only when chosen. MariaDB's own repo setup script. You type the password. `GRANT ALL` without `WITH GRANT OPTION` |
| Database in the app | `php artisan p:environment:database` with the MySQL driver, then `php artisan migrate --seed --force` | Not run. The docs say to enter the database in the web installer |
| App URL | `php artisan key:generate --force`, `p:environment:setup`, then `sed` sets `APP_URL` and `APP_INSTALLED=true` | `p:environment:setup`, then `APP_URL` is set to the address you chose. `APP_INSTALLED` is left for the web installer |
| Admin user | `php artisan p:user:make` with email, username `admin`, and the password you set | Not created |
| Cron | `* * * * * php /var/www/pelican/artisan schedule:run` for `www-data` | Same line, from `scripts/post-install.sh`, after the browser installer sets `APP_INSTALLED=true` |
| Queue | `php artisan p:environment:queue-service`, then `pelican-queue` is enabled and started | Same command with `--overwrite`, from `scripts/post-install.sh`, after the browser installer |
| Ownership | `chown -R www-data:www-data` at the end on Debian and Ubuntu | Same `chown`, after setup, plus `chmod -R 755` on `storage/*` and `bootstrap/cache/` |
| Firewall | Optional UFW, ports 22, 80, and 443 | Optional UFW. SSH uses the port of this session and the ports from `sshd -T`, then 80, 443, and Wings 8080 and 2022 |
| Let's Encrypt | `certbot --nginx` when you opt in. Refuses an IP | Same command when Nginx and HTTPS are selected. Caddy does not use Certbot. Wings can still use Certbot standalone |
| Existing install | Warns if `/var/www/pelican` already exists | Asks before unpacking over a directory that already has `artisan`. A non-interactive run stops |

## Why the browser showed `panel.test`

`.env.example` sets `APP_URL=http://panel.test`. Pelinstaller overwrites that with `http://` or `https://` plus the hostname you entered. This installer now does the same with the IP or domain from its prompt. Before that change, `/installer` loaded, and the CSS and JavaScript requests went to `panel.test` and failed with `ERR_NAME_NOT_RESOLVED`.

## Left out on purpose

Apache is still not installed. The queue worker and the panel cron are not part of `install.sh`; `scripts/post-install.sh` adds them after the browser installer. Wings does not create a MariaDB user for panel database hosts, and it does not open MySQL to the network. The panel Docker path uses the official compose file, not Pelinstaller's MariaDB and Redis stack.
