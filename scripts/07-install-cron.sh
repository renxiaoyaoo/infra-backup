#!/bin/bash
set -euo pipefail
umask 077

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CRON_FILE="$(mktemp)"
trap 'rm -f "$CRON_FILE"' EXIT

{
  crontab -l 2>/dev/null | awk '
    BEGIN { skip=0 }
    /^# infra-backup begin$/ { skip=1; next }
    /^# infra-backup end$/ { skip=0; next }
    skip == 0 { print }
  '

  cat <<EOF

# infra-backup begin
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 3 * * * $BASE/scripts/06-backup-all.sh
0 5 * * 0 $BASE/scripts/04-restic-check.sh
# infra-backup end
EOF
} > "$CRON_FILE"

crontab "$CRON_FILE"
echo "installed crontab block for infra-backup"
