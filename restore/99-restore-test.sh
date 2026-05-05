#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"

TS="$(date +%F-%H%M%S)"
TEST_DIR="/tmp/infra-backup-restore-test"
LOG="$LOG_DIR/restore-test-$TS.log"

mkdir -p "$TEST_DIR" "$LOG_DIR"
chmod 700 "$TEST_DIR" "$LOG_DIR" 2>/dev/null || true

{
  echo "===== restore test start: $TS ====="

  echo "--- latest local backups ---"
  find "$LOCAL_BACKUP_DIR" -type f -name "*.tar.gz" | sort -r | head -10

  LATEST="$(find "$LOCAL_BACKUP_DIR/pi" -maxdepth 1 -type f -name "pi-infra-backup-*.tar.gz" | sort -r | head -1 || true)"

  if [ -n "$LATEST" ]; then
    echo
    echo "--- test extract latest pi backup ---"
    echo "$LATEST"
    rm -rf "$TEST_DIR/pi"
    mkdir -p "$TEST_DIR/pi"
    tar -tzf "$LATEST" | head -80
    tar -xzf "$LATEST" -C "$TEST_DIR/pi"
    echo "restore test dir: $TEST_DIR/pi"
  else
    echo "no pi local backup found"
    exit 1
  fi

  echo "Restore test OK"
} >> "$LOG" 2>&1

tail -120 "$LOG"
