#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
source "$CONF"
BACKUP_SCAN_ROOTS="${BACKUP_SCAN_ROOTS:-$HOME}"

TS="$(date +%F-%H%M%S)"
OUT_DIR="$LOCAL_BACKUP_DIR/pi"
STAGE="$(mktemp -d /tmp/infra-backup-pi-$TS.XXXXXX)"
OUT="$OUT_DIR/pi-infra-backup-$TS.tar.gz"
OUT_TMP="$OUT.tmp"
LOG="$LOG_DIR/pi-local-backup-$TS.log"

mkdir -p "$OUT_DIR" "$STAGE" "$LOG_DIR"
chmod 700 "$LOCAL_BACKUP_DIR" "$OUT_DIR" "$LOG_DIR" 2>/dev/null || true
chmod 700 "$STAGE" 2>/dev/null || true

cleanup() {
  rm -f "$OUT_TMP"
  rm -rf "$STAGE"
}
trap cleanup EXIT

{
  echo "===== Pi local backup start: $TS ====="

  mkdir -p "$STAGE/meta"

  hostname > "$STAGE/meta/hostname.txt" 2>/dev/null || true
  uname -a > "$STAGE/meta/uname.txt" 2>/dev/null || true
  df -h > "$STAGE/meta/df-h.txt" 2>/dev/null || true
  ip addr > "$STAGE/meta/ip-addr.txt" 2>/dev/null || true
  ip route > "$STAGE/meta/ip-route-v4.txt" 2>/dev/null || true
  ip -6 route > "$STAGE/meta/ip-route-v6.txt" 2>/dev/null || true
  crontab -l > "$STAGE/meta/crontab-pi.txt" 2>/dev/null || true
  systemctl list-unit-files > "$STAGE/meta/systemd-unit-files.txt" 2>/dev/null || true
  systemctl list-timers > "$STAGE/meta/systemd-timers.txt" 2>/dev/null || true
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' > "$STAGE/meta/docker-ps.txt" 2>/dev/null || true
  docker compose ls > "$STAGE/meta/docker-compose-ls.txt" 2>/dev/null || true
  { find $BACKUP_SCAN_ROOTS -maxdepth 4 -type f \( -name "docker-compose*.yml" -o -name "compose*.yml" -o -name ".env" \) 2>/dev/null || true; } | sort > "$STAGE/meta/docker-compose-files.txt"

  cp "$CONF" "$STAGE/meta/backup.conf"

  PATH_LIST="$STAGE/meta/path-list.txt"
  : > "$PATH_LIST"

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ -e "$p" ] && echo "$p" >> "$PATH_LIST"
  done <<PATHS
$BACKUP_PATHS
PATHS

  while IFS='|' read -r dir pattern; do
    [ -z "${dir:-}" ] && continue
    [ -z "${pattern:-}" ] && continue
    latest_file="$(
      find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr \
        | awk 'NR == 1 { $1=""; sub(/^ /, ""); print }'
    )"
    [ -n "$latest_file" ] && echo "$latest_file" >> "$PATH_LIST"
  done <<LATEST_FILES
${LATEST_FILE_DIRS:-}
LATEST_FILES

  sort -u "$PATH_LIST" -o "$PATH_LIST"

  STAGED_PATH_LIST="$STAGE/meta/staged-path-list.txt"
  SKIP_PATH_LIST="$STAGE/meta/staged-skip-list.txt"
  : > "$STAGED_PATH_LIST"
  : > "$SKIP_PATH_LIST"

  while IFS='|' read -r src dest; do
    [ -z "${src:-}" ] && continue
    [ -z "${dest:-}" ] && continue
    if command -v docker >/dev/null 2>&1; then
      stage_dest="$STAGE/rootfs/${dest#/}"
      mkdir -p "$stage_dest"
      if docker cp "$src/." "$stage_dest/"; then
        echo "$dest" >> "$SKIP_PATH_LIST"
        echo "${dest#/}" >> "$STAGED_PATH_LIST"
      else
        rm -rf "$stage_dest"
      fi
    fi
  done <<CONTAINER_PATHS
${CONTAINER_COPY_DIRS:-}
CONTAINER_PATHS

  if [ -s "$SKIP_PATH_LIST" ]; then
    FILTERED_PATH_LIST="$STAGE/meta/path-list.filtered.txt"
    grep -Fvx -f "$SKIP_PATH_LIST" "$PATH_LIST" > "$FILTERED_PATH_LIST" || true
    PATH_LIST="$FILTERED_PATH_LIST"
  fi

  if [ ! -s "$PATH_LIST" ]; then
    echo "ERROR: no configured backup paths exist"
    exit 1
  fi

  EXCLUDE_FILE="$STAGE/meta/exclude-list.txt"
  {
    echo "/tmp/infra-backup-pi-*/"
    echo "$LOCAL_BACKUP_DIR/"
    echo "$LOG_DIR/"
    echo "$BASE/local-backups/"
    echo "$BASE/logs/*"
    echo "$EXCLUDE_PATHS"
  } > "$EXCLUDE_FILE"

  echo "--- paths to backup ---"
  cat "$PATH_LIST"
  if [ -s "$STAGED_PATH_LIST" ]; then
    echo "--- staged container paths ---"
    cat "$STAGED_PATH_LIST"
  fi

  echo "--- archive mode: local tar with staged container copies ---"
  tar_args=(
    --exclude-from="$EXCLUDE_FILE"
    -czf "$OUT_TMP"
    -T "$PATH_LIST"
  )
  if [ -s "$STAGED_PATH_LIST" ]; then
    tar_args+=(-C "$STAGE/rootfs" -T "$STAGED_PATH_LIST")
  fi
  tar_args+=(-C "$STAGE" meta)
  tar "${tar_args[@]}"

  chmod 600 "$OUT_TMP"
  mv "$OUT_TMP" "$OUT"

  echo "--- result ---"
  ls -lh "$OUT"

  echo "Pi local backup OK"
} >> "$LOG" 2>&1

echo "$OUT"
echo "$LOG"
