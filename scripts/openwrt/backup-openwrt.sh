#!/bin/sh
set -eu
umask 077

BASE="/root/infra-backup"
. "$BASE/config.env"

DATE="$(date +%F-%H%M%S)"
HOST="$(hostname 2>/dev/null || echo openwrt)"
WORK="/tmp/openwrt-infra-backup-$DATE"
OUT="/tmp/openwrt-infra-backup-$HOST-$DATE.tar.gz"
LOG="$BASE/logs/backup-openwrt.log"
mkdir -p "$BASE/logs"

log() {
  echo "$*"
  echo "$(date '+%F %T') $*" >> "$LOG"
}

cleanup() {
  rm -rf "$WORK" "$OUT"
}
trap cleanup EXIT

mkdir -p "$WORK/meta" "$WORK/etc" "$WORK/root" "$WORK/runtime" "$WORK/services"

log "start openwrt backup: $DATE"

# 官方 sysupgrade 备份
sysupgrade -b "$WORK/sysupgrade-$HOST-$DATE.tar.gz"

# 配置文件
cp -a /etc/config "$WORK/etc/config" 2>/dev/null || true
[ -f /etc/crontabs/root ] && mkdir -p "$WORK/etc/crontabs" && cp -a /etc/crontabs/root "$WORK/etc/crontabs/root"
[ -f /etc/init.d/mihomo-watchdog ] && cp -a /etc/init.d/mihomo-watchdog "$WORK/services/mihomo-watchdog"

# root 下关键脚本
for f in /root/*.sh /root/*mihomo* /root/*backup*; do
  [ -f "$f" ] && cp -a "$f" "$WORK/root/" || true
done

# 只单独保留本机安装配置，不打包整个 /root/infra-backup
mkdir -p "$WORK/root/infra-backup"
[ -f "$BASE/config.env" ] && cp -a "$BASE/config.env" "$WORK/root/infra-backup/config.env"

# 运行态网络快照
uci export > "$WORK/runtime/uci-export.txt" 2>&1 || true
iptables-save > "$WORK/runtime/iptables-save.txt" 2>&1 || true
ip6tables-save > "$WORK/runtime/ip6tables-save.txt" 2>&1 || true
ip rule > "$WORK/runtime/ip-rule-v4.txt" 2>&1 || true
ip -6 rule > "$WORK/runtime/ip-rule-v6.txt" 2>&1 || true
ip route show table 100 > "$WORK/runtime/route-table100-v4.txt" 2>&1 || true
ip -6 route show table all | grep 'table 100' > "$WORK/runtime/route-table100-v6.txt" 2>&1 || true

# 系统信息
opkg list-installed > "$WORK/meta/opkg-list-installed.txt" 2>&1 || true
df -h > "$WORK/meta/df-h.txt" 2>&1 || true
free > "$WORK/meta/free.txt" 2>&1 || true
ls -la /root > "$WORK/meta/root-ls.txt" 2>&1 || true
ls -la /etc/init.d > "$WORK/meta/initd-ls.txt" 2>&1 || true
ls -la /etc/rc.d > "$WORK/meta/rcd-ls.txt" 2>&1 || true

tar -czf "$OUT" -C "$WORK" .
chmod 600 "$OUT"

ssh -i "$SSH_KEY" "$PI_SSH" "mkdir -p '$PI_BACKUP_DIR'"
scp -i "$SSH_KEY" "$OUT" "$PI_SSH:$PI_BACKUP_DIR/"

log "uploaded: $PI_SSH:$PI_BACKUP_DIR/$(basename "$OUT")"
log "openwrt backup ok"
