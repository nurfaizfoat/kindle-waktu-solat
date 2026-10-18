#!/bin/sh
# Provision the VPS for the Kindle waktu board. Run as root ON the VPS.
#
#   DOMAIN=waktu.example.com sh setup-server.sh
#   DOMAIN=waktu.example.com sh setup-server.sh --no-tls
#
# Idempotent: packages and the nginx site are installed only when missing or
# changed. The board tree itself is copied separately by deploy.sh.
#
# --no-tls is for the first run, before DNS points at this host. Run again
# without the flag (or run certbot directly) once DNS resolves.
set -eu

DOMAIN=${DOMAIN:-}
TLS=1
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE=${TEMPLATE:-$SCRIPT_DIR/nginx-waktu.conf}
for arg in "$@"; do
    case "$arg" in
        --no-tls) TLS=0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

[ -n "$DOMAIN" ] || { echo "DOMAIN is required (e.g. DOMAIN=waktu.example.com)" >&2; exit 2; }
[ -f "$TEMPLATE" ] || { echo "nginx template not found: $TEMPLATE" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 || true)
[ -n "$PHP_SOCK" ] || PHP_SOCK=/run/php/php-fpm.sock

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx php-fpm php-gd php-curl certbot python3-certbot-nginx

# Board renderer needs a little more room than the PHP default; the server is
# 2 GB, so keep the limit modest.
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
cat >"/etc/php/$PHP_VER/fpm/conf.d/99-waktu.ini" <<'EOF'
memory_limit = 256M
max_execution_time = 60
date.timezone = Asia/Kuala_Lumpur
EOF
systemctl restart "php$PHP_VER-fpm"

# Repository layout: /var/www/waktu/board.php
install -d -o root -g root -m 0755 /var/www/waktu
install -d -o www-data -g www-data -m 0755 /var/www/waktu/data /var/www/waktu/out

sed -e "s|__DOMAIN__|$DOMAIN|g" \
    -e "s|__PHP_SOCK__|$PHP_SOCK|g" \
    "$TEMPLATE" >/etc/nginx/sites-available/waktu
ln -sfn /etc/nginx/sites-available/waktu /etc/nginx/sites-enabled/waktu
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable --now nginx
systemctl reload nginx

# The board reads data/ and writes data/ + out/ as www-data.
chown -R www-data:www-data /var/www/waktu/data /var/www/waktu/out
find /var/www/waktu/data /var/www/waktu/out -type d -exec chmod 0755 {} +
find /var/www/waktu/data /var/www/waktu/out -type f -exec chmod 0644 {} +

# Keep SSH reachable before enabling the firewall.
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

if [ "$TLS" -eq 1 ]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
        --register-unsafely-without-email --redirect
fi

echo
echo "Setup complete for $DOMAIN"
echo "  runtime: PHP $PHP_VER via $PHP_SOCK"
echo "  root:    /var/www/waktu"
