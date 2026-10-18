# VPS deployment

The live board runs on a small Ubuntu VPS: nginx + PHP-FPM + GD, with the
`deploy/stage/waktu/` tree as the document root.

- Public URL: `https://waktu.example.com/waktu/board.php` (example placeholder;
  the real domain is kept in the gitignored `deploy/vps/vps.env`).
- Server path: `/var/www/waktu/`
- Only `board.php` is executable over HTTP. `render.php` and `fetch.php` are
  CLI-only, and `data/`, `assets/`, `out/` are denied by nginx.
- `data/` and `out/` are owned by `www-data`, because `board.php` refreshes the
  JAKIM snapshot and writes `out/board.png`.

## Local overrides

The public repository contains only placeholders. Create the gitignored
`deploy/vps/vps.env` with the real values:

```sh
HOST=root@YOUR_VPS_IP
DOMAIN=waktu.example.com
SSH_KEY=$HOME/.ssh/id_ed25519
```

`deploy.sh` sources that file when present. The same values can be supplied as
environment variables instead.

## First-time setup

1. Add the DNS record: `A waktu -> <VPS IPv4>` (TTL default). Do not proxy it
   through a CDN; the Kindle cannot solve a bot/JS challenge.

   If the registrar is not the DNS host, add the record at the delegated DNS
   provider (cPanel Zone Editor or their client area). Do not switch nameservers
   just for one record: that would require recreating every existing record
   first.

2. Run the deployment with TLS disabled, because the certificate cannot be
   issued before DNS resolves:

   ```sh
   ./deploy/vps/deploy.sh --no-tls
   ```

3. Verify over HTTP using the VPS IP and a Host header:

   ```sh
   curl -s -o /tmp/board.png -H 'Host: waktu.example.com' \
       http://YOUR_VPS_IP/waktu/board.php
   file /tmp/board.png
   ```

4. Once DNS resolves, run again to obtain/renew the certificate and enable the
   HTTP -> HTTPS redirect:

   ```sh
   ./deploy/vps/deploy.sh
   ```

5. Point the Kindle at the URL in `/mnt/us/dashboard/board-url.conf`:

   ```sh
   BOARD_URL="https://waktu.example.com/waktu/board.php"
   ```

## Redeploying after a code change

`deploy.sh` is idempotent. It copies `deploy/stage/waktu/` and `/root/kindle-deploy/`,
then reruns `setup-server.sh`. Generated files under `out/` and the JAKIM
snapshot are left in place (no `--delete` on the webroot).

When `dashboard/lib.php` changes, copy it to `deploy/stage/waktu/lib.php` first
and confirm the two are byte-identical (`cmp`), as the repository requires.

## Operations

```sh
systemctl status nginx php8.5-fpm
tail -f /var/log/nginx/waktu.error.log
certbot renew --dry-run          # renewal timer is installed by certbot
curl -sI https://waktu.example.com/waktu/board.php
```

The certificate is a normal Let's Encrypt certificate, trusted by the Kindle's
curl. The response is a PNG of exactly 1072x1448 with `Cache-Control: no-store`.
