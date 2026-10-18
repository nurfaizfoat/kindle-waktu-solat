#!/bin/sh
# Deploy the board tree and server config to the VPS, then run setup-server.sh.
#
#   ./deploy/vps/deploy.sh              # install/redeploy, with TLS
#   ./deploy/vps/deploy.sh --no-tls     # first run, before DNS points here
#
# Override defaults with environment variables:
#   HOST=root@1.2.3.4 DOMAIN=waktu.example.com SSH_KEY=~/.ssh/id_ed25519 ...
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

# Optional local overrides (gitignored): keeps the real host/domain out of the
# public repository. See README.md.
if [ -f "$SCRIPT_DIR/vps.env" ]; then
    . "$SCRIPT_DIR/vps.env"
fi

HOST=${HOST:-root@YOUR_VPS_IP}
DOMAIN=${DOMAIN:-waktu.example.com}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/id_ed25519}

SSH="ssh -i $SSH_KEY -o BatchMode=yes"
SCP_HOST=${HOST#*@}

$SSH "$HOST" 'rm -rf /root/kindle-deploy && mkdir -p /root/kindle-deploy /var/www/waktu'
rsync -a --delete --exclude vps.env -e "ssh -i $SSH_KEY -o BatchMode=yes" \
    "$SCRIPT_DIR/" "$HOST:/root/kindle-deploy/"

# The staging tree is the deployable copy (no tests, no php_check.php).
# Do not --delete: the server keeps its generated out/board.png and snapshots.
rsync -a -e "ssh -i $SSH_KEY -o BatchMode=yes" \
    "$REPO_DIR/deploy/stage/waktu/" "$HOST:/var/www/waktu/"

$SSH "$HOST" "chown -R root:root /var/www/waktu && \
    chown -R www-data:www-data /var/www/waktu/data /var/www/waktu/out && \
    DOMAIN='$DOMAIN' sh /root/kindle-deploy/setup-server.sh $*"

echo "Deployed $DOMAIN to $SCP_HOST"
