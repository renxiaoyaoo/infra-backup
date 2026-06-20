#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"

TS="$(date +%F-%H%M%S)"
LOG="$LOG_DIR/clean-local-$TS.log"

mkdir -p "$LOG_DIR"

{
  [ -d "$OPENWRT_LOCAL_DIR" ] && find "$OPENWRT_LOCAL_DIR" -maxdepth 1 -type f -name "openwrt-infra-backup-*.tar.gz" | sort -r | tail -n +$((KEEP_LOCAL_OPENWRT + 1)) | xargs -r rm -f
  [ -d "$LOCAL_BACKUP_DIR/pi" ] && find "$LOCAL_BACKUP_DIR/pi" -maxdepth 1 -type f -name "pi-infra-backup-*.tar.gz" | sort -r | tail -n +$((KEEP_LOCAL_PI + 1)) | xargs -r rm -f
  for host in ${CLOUD_HOSTS:-}; do
    find "${CLOUD_BACKUP_DIR:-$LOCAL_BACKUP_DIR/cloud}" -maxdepth 1 -type f -name "${host}-infra-backup-*.tar.gz" 2>/dev/null | sort -r | tail -n +$((KEEP_LOCAL_CLOUD + 1)) | xargs -r rm -f
  done
  echo "clean local OK"
} >> "$LOG" 2>&1

echo "$LOG"
