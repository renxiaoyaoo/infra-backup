#!/bin/bash
set -u
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$BASE/config/backup.conf"
[ -f "$CONF" ] && source "$CONF"

BASE="${BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="${LOG_DIR:-$BASE/logs}"
BACKUP_SCAN_ROOTS="${BACKUP_SCAN_ROOTS:-$HOME /usr/local/bin /etc/systemd/system}"
RESTIC_ENV="${RESTIC_ENV:-$HOME/.restic-r2-env}"
REPORT="$LOG_DIR/inventory-report.txt"

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR" 2>/dev/null || true

{
  echo "===== INVENTORY TIME ====="
  date

  echo
  echo "===== HOST ====="
  hostname
  uname -a
  df -h /

  echo
  echo "===== INFRA BACKUP TREE ====="
  find "$BASE" -maxdepth 3 -type d | sort

  echo
  echo "===== CRON ====="
  echo "--- user crontab ---"
  crontab -l 2>/dev/null || true
  echo "--- /etc/crontab ---"
  cat /etc/crontab 2>/dev/null || true
  echo "--- /etc/cron.d ---"
  ls -la /etc/cron.d 2>/dev/null || true

  echo
  echo "===== SYSTEMD BACKUP/RESTIC SERVICES ====="
  systemctl list-unit-files 2>/dev/null | grep -Ei 'backup|restic|rclone|infra' || true
  systemctl list-timers 2>/dev/null | grep -Ei 'backup|restic|rclone|infra' || true

  echo
  echo "===== DOCKER CONTAINERS ====="
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || true

  echo
  echo "===== DOCKER COMPOSE FILES ====="
  find $BACKUP_SCAN_ROOTS -maxdepth 4 -type f \( -name "docker-compose*.yml" -o -name "compose*.yml" -o -name ".env" \) 2>/dev/null | sort

  echo
  echo "===== BACKUP / MIHOMO / OPENWRT SCRIPTS ====="
  find $BACKUP_SCAN_ROOTS -maxdepth 4 -type f \( \
    -iname "*backup*" -o \
    -iname "*restic*" -o \
    -iname "*mihomo*" -o \
    -iname "*openwrt*" \
  \) 2>/dev/null | sort

  echo
  echo "===== RESTIC ====="
  which restic 2>/dev/null || true
  restic version 2>/dev/null || true

  echo
  echo "===== RESTIC ENV MASKED ====="
  if [ -f "$RESTIC_ENV" ]; then
    sed -E 's/(PASSWORD|SECRET|KEY|TOKEN|ACCESS_KEY_ID|SECRET_ACCESS_KEY|RESTIC_PASSWORD)=.*/\1=MASKED/g' "$RESTIC_ENV"
  fi

  echo
  echo "===== BACKUP PATHS FROM CONFIG ====="
  echo "${BACKUP_PATHS:-}"

  echo
  echo "===== EXISTING LOCAL BACKUPS ====="
  find "${LOCAL_BACKUP_DIR:-$BASE/local-backups}" -maxdepth 4 \( -type f -o -type d \) 2>/dev/null | sort

} > "$REPORT" 2>&1
chmod 600 "$REPORT" 2>/dev/null || true

echo "$REPORT"
