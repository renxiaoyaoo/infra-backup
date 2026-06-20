#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"

TS="$(date +%F-%H%M%S)"
OUT_DIR="${CLOUD_BACKUP_DIR:-$LOCAL_BACKUP_DIR/cloud}"
LOG="$LOG_DIR/cloud-backup-$TS.log"

mkdir -p "$OUT_DIR" "$LOG_DIR"
chmod 700 "$OUT_DIR" "$LOG_DIR" 2>/dev/null || true

{
  echo "===== Cloud backup start: $TS ====="
  paths="$(printf '%s\n' "$CLOUD_BACKUP_PATHS" | awk 'NF {printf "%s ", $0}')"
  if [ -z "$paths" ]; then
    echo "ERROR: no cloud backup paths configured"
    exit 1
  fi
  for host in ${CLOUD_HOSTS:-}; do
    out="$OUT_DIR/${host}-infra-backup-$TS.tar.gz"
    tmp="$out.tmp"
    echo "--- $host ---"
    ssh "$host" "tar -C \"\$HOME\" -czf - $paths" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    tar -tzf "$out" >/dev/null
    ls -lh "$out"
  done
  echo "Cloud backup OK"
} >> "$LOG" 2>&1

echo "$LOG"
