#!/bin/bash
set -euo pipefail

BASE="${INFRA_BACKUP_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

"$BASE/scripts/00-inventory.sh" || true
"$BASE/scripts/02-backup-pi-local.sh"
"$BASE/scripts/01-backup-openwrt-pull.sh"
"$BASE/scripts/03-restic-backup-r2.sh"
"$BASE/scripts/05-clean-local.sh"
