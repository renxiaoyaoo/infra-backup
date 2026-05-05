#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"

if [ ! -f "$RESTIC_ENV" ]; then
  echo "missing restic env: $RESTIC_ENV" >&2
  exit 1
fi
set +u
source "$RESTIC_ENV"
set -u

TS="$(date +%F-%H%M%S)"
LOG="$LOG_DIR/restic-check-$TS.log"

mkdir -p "$LOG_DIR"

{
  echo "===== Restic check start: $TS ====="
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u NO_PROXY -u no_proxy restic snapshots
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u NO_PROXY -u no_proxy restic check --read-data-subset=5%
  echo "--- restic raw stats ---"
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u NO_PROXY -u no_proxy restic stats --mode raw-data
  echo "Restic check OK"
} >> "$LOG" 2>&1

echo "$LOG"
