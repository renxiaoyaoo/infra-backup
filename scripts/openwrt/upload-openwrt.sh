#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"

OPENWRT_HOST="${OPENWRT_HOST:-root@openwrt.lan}"
OPENWRT_REMOTE_DIR="${OPENWRT_REMOTE_DIR:-/root/infra-backup}"
SRC_DIR="$BASE/scripts/openwrt"

for f in "$SRC_DIR/backup-openwrt.sh" "$SRC_DIR/config.env"; do
  [ -f "$f" ] || { echo "missing file: $f" >&2; exit 1; }
done

ssh -F /dev/null "$OPENWRT_HOST" "mkdir -p '$OPENWRT_REMOTE_DIR' '$OPENWRT_REMOTE_DIR/logs'"
scp -O -F /dev/null "$SRC_DIR/backup-openwrt.sh" "$SRC_DIR/config.env" "$OPENWRT_HOST:$OPENWRT_REMOTE_DIR/"

ssh -F /dev/null "$OPENWRT_HOST" "chmod 700 '$OPENWRT_REMOTE_DIR/backup-openwrt.sh' && chmod 600 '$OPENWRT_REMOTE_DIR/config.env'"

echo "uploaded to $OPENWRT_HOST:$OPENWRT_REMOTE_DIR"
