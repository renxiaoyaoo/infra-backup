#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"

TS="$(date +%F-%H%M%S)"
LOG="$LOG_DIR/openwrt-backup-$TS.log"

mkdir -p "$OPENWRT_LOCAL_DIR" "$LOG_DIR"
chmod 700 "$LOCAL_BACKUP_DIR" "$OPENWRT_LOCAL_DIR" "$LOG_DIR" 2>/dev/null || true

{
  echo "===== OpenWrt backup start: $TS ====="

  echo "--- run remote backup script ---"
  ssh -F /dev/null "$OPENWRT_HOST" "$OPENWRT_REMOTE_DIR/backup-openwrt.sh"

  echo "--- local result ---"
  find "$OPENWRT_LOCAL_DIR" -maxdepth 1 -type f -name "openwrt-infra-backup-*.tar.gz" 2>/dev/null | sort | tail -5
  ls -lh "$OPENWRT_LOCAL_DIR" | tail -20

  echo "OpenWrt backup OK"
} >> "$LOG" 2>&1

echo "$LOG"
