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
LOG="$LOG_DIR/restic-backup-$TS.log"
LATEST_PI="$(find "$LOCAL_BACKUP_DIR/pi" -maxdepth 1 -type f -name 'pi-infra-backup-*.tar.gz' 2>/dev/null | sort | tail -1 || true)"
LATEST_OPENWRT="$(find "$LOCAL_BACKUP_DIR/openwrt" -maxdepth 1 -type f -name 'openwrt-infra-backup-*.tar.gz' 2>/dev/null | sort | tail -1 || true)"
RESTIC_SOURCES=()
RESTIC_CMD=(env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u NO_PROXY -u no_proxy restic)
RESTIC_ERR="$(mktemp)"
trap 'rm -f "$RESTIC_ERR"' EXIT

[ -n "$LATEST_PI" ] && RESTIC_SOURCES+=("$LATEST_PI")
[ -n "$LATEST_OPENWRT" ] && RESTIC_SOURCES+=("$LATEST_OPENWRT")
for host in ${CLOUD_HOSTS:-}; do
  latest_cloud="$(find "${CLOUD_BACKUP_DIR:-$LOCAL_BACKUP_DIR/cloud}" -maxdepth 1 -type f -name "${host}-infra-backup-*.tar.gz" 2>/dev/null | sort | tail -1 || true)"
  [ -n "$latest_cloud" ] && RESTIC_SOURCES+=("$latest_cloud")
done

mkdir -p "$LOG_DIR"

{
  echo "===== Restic backup start: $TS ====="
  echo "--- latest pi backup ---"
  [ -n "$LATEST_PI" ] && echo "$LATEST_PI" || echo "none"
  echo "--- latest openwrt backup ---"
  [ -n "$LATEST_OPENWRT" ] && echo "$LATEST_OPENWRT" || echo "none"
  echo "--- latest cloud backups ---"
  for host in ${CLOUD_HOSTS:-}; do
    find "${CLOUD_BACKUP_DIR:-$LOCAL_BACKUP_DIR/cloud}" -maxdepth 1 -type f -name "${host}-infra-backup-*.tar.gz" 2>/dev/null | sort | tail -1 || echo "$host: none"
  done

  if ! "${RESTIC_CMD[@]}" snapshots >/dev/null 2>"$RESTIC_ERR"; then
    if grep -qi 'repository does not exist' "$RESTIC_ERR"; then
      echo "--- init restic repository ---"
      "${RESTIC_CMD[@]}" init
    else
      cat "$RESTIC_ERR" >&2
      exit 1
    fi
  fi

  if [ "${#RESTIC_SOURCES[@]}" -gt 0 ]; then
    "${RESTIC_CMD[@]}" backup "${RESTIC_SOURCES[@]}" \
      --tag "$RESTIC_TAG" \
      --verbose
  else
    echo "no local backup files found"
    exit 1
  fi

  "${RESTIC_CMD[@]}" forget \
    --tag "$RESTIC_TAG" \
    --group-by tags \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --prune

  echo "--- restic raw stats ---"
  "${RESTIC_CMD[@]}" stats --mode raw-data

  echo "Restic backup OK"
} >> "$LOG" 2>&1

echo "$LOG"
