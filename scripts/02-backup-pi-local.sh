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
LOG="$LOG_DIR/pi-local-backup-$TS.log"

mkdir -p "$OUT_DIR" "$STAGE" "$LOG_DIR"
chmod 700 "$LOCAL_BACKUP_DIR" "$OUT_DIR" "$LOG_DIR" 2>/dev/null || true
chmod 700 "$STAGE" 2>/dev/null || true

cleanup() {
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

  DOCKER_PATH_LIST="$STAGE/meta/path-list.docker.txt"
  DOCKER_EXCLUDE_FILE="$STAGE/meta/exclude-list.docker.txt"
  sed 's#^/##' "$PATH_LIST" > "$DOCKER_PATH_LIST"
  sed 's#^/##' "$EXCLUDE_FILE" > "$DOCKER_EXCLUDE_FILE"

  if command -v docker >/dev/null 2>&1 && docker image inspect "${TAR_IMAGE:-caddy:2}" >/dev/null 2>&1; then
    echo "--- archive mode: docker root readonly tar (${TAR_IMAGE:-caddy:2}) ---"
    docker run --rm \
      --network none \
      -v /:/host:ro \
      -v "$STAGE":/stage:ro \
      --entrypoint tar \
      "${TAR_IMAGE:-caddy:2}" \
      -czf - \
      -X /stage/meta/exclude-list.docker.txt \
      -C /host \
      -T /stage/meta/path-list.docker.txt \
      -C /stage meta > "$OUT"
  else
    echo "--- archive mode: local tar ---"
    tar \
      --exclude-from="$EXCLUDE_FILE" \
      -czf "$OUT" \
      -T "$PATH_LIST" \
      -C "$STAGE" meta
  fi

  chmod 600 "$OUT"

  echo "--- result ---"
  ls -lh "$OUT"

  echo "Pi local backup OK"
} >> "$LOG" 2>&1

echo "$OUT"
echo "$LOG"
