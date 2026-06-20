#!/bin/bash
set -euo pipefail

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS=0

run_required() {
  "$@" || STATUS=$?
}

"$BASE/scripts/00-inventory.sh" || true
run_required "$BASE/scripts/02-backup-pi-local.sh"
run_required "$BASE/scripts/01-backup-openwrt-pull.sh"
run_required "$BASE/scripts/08-backup-cloud-hosts.sh"
run_required "$BASE/scripts/03-restic-backup-r2.sh"

# Always trim local backup archives, even when upload/restic fails.
"$BASE/scripts/05-clean-local.sh" || STATUS=$?

exit "$STATUS"
