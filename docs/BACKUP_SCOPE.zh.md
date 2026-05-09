# 备份范围和仓库职责

这份文档记录 `infra-backup` 当前按树莓派真实运行状态备份哪些文件、忽略哪些文件，以及它和 `dotfiles`、`raspberry-conf` 的边界。

## 结论

`infra-backup` 有必要保留。它不保存被备份文件本身，而是保存备份脚本、备份范围、恢复验证流程和远端上传流程。

`raspberry-conf` 可以逐步退役，但不要直接拿 `infra-backup` 当服务运行目录。更合理的方式是：

- 运行时配置继续放在树莓派实际路径，例如 `/home/pi/docker-compose.yml`、`/home/pi/ha/config`。
- `infra-backup` 负责把这些实际路径打包、验证、上传。
- 等确认恢复流程足够可靠后，再决定是否删除 `raspberry-conf` 这个历史仓库。

`dotfiles` 只管用户级环境，不管服务栈私有配置。

## 已执行验证

已在树莓派上按当前真实文件执行过：

```bash
cd ~/infra-backup
git pull --ff-only
cp config/backup.conf.example config/backup.conf
chmod 600 config/backup.conf
./scripts/02-backup-pi-local.sh
./restore/99-restore-test.sh
```

验证结果：

- 生成 Pi 本地备份包：`/home/pi/infra-backup/local-backups/pi/pi-infra-backup-2026-05-10-032548.tar.gz`
- 生成备份日志：`/home/pi/infra-backup/logs/pi-local-backup-2026-05-10-032548.log`
- 生成恢复验证日志：`/home/pi/infra-backup/logs/restore-test-2026-05-10-032614.log`
- 恢复测试成功，备份包可以解开并列出关键文件。

注意：部分 Docker volume 里的配置文件属于 root，例如 AdGuard Home 和 wg-easy 生成的文件。Pi 用户没有 sudo 免密权限，所以 Pi 本地备份会先用 `docker cp` 从正在运行的容器复制这些配置到临时 staging，再按原路径放进备份包。这样 cron 可以无人值守执行，同时不会修改被备份文件。

## 仓库里包含什么

这些文件应该提交到 Git：

- `README.md`：整体说明、部署位置、手动命令。
- `docs/BACKUP_SCOPE.zh.md`：当前备份范围和职责边界。
- `config/backup.conf.example`：备份范围模板，不含真实密钥。
- `scripts/*.sh`：Pi 侧备份、清理、restic 上传、恢复验证脚本。
- `scripts/openwrt/*.sh`：同步到 OpenWrt 的备份脚本模板。
- `scripts/openwrt/config.env.example`：OpenWrt 侧配置模板，不含真实密钥。
- `logs/.gitkeep`、`local-backups/*/.gitkeep`：保留空目录结构。

这些文件不应该提交到 Git：

- `config/backup.conf`：Pi 侧真实配置，可能含真实路径、主机名、参数。
- `config/backup.conf.bak.*`：本地配置快照。
- `scripts/openwrt/config.env`：OpenWrt 侧真实配置。
- `logs/*`：运行日志。
- `local-backups/pi/*`：Pi 本地备份包。
- `local-backups/openwrt/*`：OpenWrt 本地备份包。
- `.DS_Store`、`*.log`、`*.tmp`、`*.cache`、`__pycache__/`、`.agents/`、`.codex/`：本地噪音。

## Pi 侧要备份的文件

这些路径来自树莓派当前实际运行状态。重点不是备份仓库副本，而是备份服务真正读取的文件。

### 服务入口

- `/home/pi/docker-compose.yml`
- `/home/pi/.env`

这两个文件决定主服务栈如何启动，以及容器使用哪些环境变量。需要备份。

### 主 compose 里的其它服务状态

- `/home/pi/.cloudflared`
- `/home/pi/filebrowser/config`
- `/home/pi/filebrowser/database`
- `/home/pi/uptime-kuma/db-config.json`
- `/home/pi/uptime-kuma/kuma.db`

这些路径来自 `/home/pi/docker-compose.yml` 里的实际 volume。`cloudflared` 当前主要靠 `.env` 里的 token 启动，但保留目录可以覆盖以后切回本地配置文件的情况。Filebrowser 和 Uptime Kuma 的配置、数据库需要备份。

### Home Assistant

- `/home/pi/ha/Dockerfile.ha`
- `/home/pi/ha/config/configuration.yaml`
- `/home/pi/ha/config/secrets.yaml`
- `/home/pi/ha/config/automations.yaml`
- `/home/pi/ha/config/scripts.yaml`
- `/home/pi/ha/config/scenes.yaml`
- `/home/pi/ha/config/backups`

Home Assistant 的 YAML、密钥、自动化、脚本、场景都属于恢复核心。`backups` 目录也要保留，因为它能帮助从 HA 自己的备份中恢复集成和状态。

### Mosquitto

- `/home/pi/mosquitto/config`
- `/home/pi/mosquitto/data`

MQTT broker 的配置和持久数据需要备份，否则 Zigbee2MQTT、HA 和其它 MQTT 客户端恢复后可能连不上或状态丢失。

### Zigbee2MQTT

- `/home/pi/zigbee2mqtt/data/configuration.yaml`
- `/home/pi/zigbee2mqtt/data/coordinator_backup.json`
- `/home/pi/zigbee2mqtt/data/database.db`
- `/home/pi/zigbee2mqtt/data/state.json`
- `/home/pi/zigbee2mqtt/data/external_converters`

这些文件决定 Zigbee 网络、设备映射、协调器备份、设备状态和自定义转换器。需要备份。

### ddns-go

- `/home/pi/.ddns-go/.ddns_go_config.yaml`

树莓派上的 ddns-go 配置以这个实际路径为准。Mac 上的 ddns-go 配置不要覆盖这里。

### network 服务栈

- `/home/pi/network/.env`
- `/home/pi/network/docker-compose.yml`
- `/home/pi/network/adguard/conf`
- `/home/pi/network/wg-easy/data`
- `/home/pi/network/mihomo/config/config.yaml`
- `/home/pi/network/mihomo/config/proxies`
- `/home/pi/network/mihomo/config/rules`
- `/home/pi/caddy/Caddyfile`

这些文件决定 network compose、AdGuard Home 配置、WireGuard 配置、mihomo 规则和 Caddy 入口。需要备份。`/home/pi/network/adguard/work` 当前体积较大，主要是运行数据和统计，不纳入默认关键配置备份。

### ha-95598

- `/home/pi/ha-95598/docker-compose.image.yml`
- `/home/pi/ha-95598/.env`
- `/home/pi/ha-95598/config`
- `/home/pi/ha-95598/data`

`ha-95598` 是树莓派上当前正在运行的独立 compose 项目，配置文件和运行数据要备份。`.git/`、`.pytest_cache/` 等开发目录由排除规则过滤。

`ha-95598/data/captcha_samples`、`ha-95598/data/pages` 和 `login_qr_code.png` 是调试截图/页面快照/临时二维码，默认不备份。真正要保留的是 session、cache 和轻量数据库。

### 系统级 glue 文件

- `/etc/systemd/system/mihomo-gateway.service`
- `/etc/systemd/system/mihomo-tproxy-route.service`
- `/etc/systemd/system/docker.service.d/proxy.conf`
- `/etc/crontab`
- `/etc/cron.d`
- `/usr/local/bin/mihomo-gateway.sh`
- `/usr/local/bin/mihomo-tproxy-route.sh`

这些是让服务启动、透明代理和定时任务正常工作的系统层文件。需要备份。

## Pi 侧忽略什么

`config/backup.conf.example` 里通过 `EXCLUDE_PATHS` 默认排除：

- 日志、临时文件、缓存：`*.log`、`*.tmp`、`*.cache`、`/cache/`、`/.cache/`
- 本地 Git 和依赖目录：`/.git/`、`/node_modules/`、`/__pycache__/`
- Python 缓存：`*.pyc`
- 备份中间文件：`*.bak`、`*.backup`
- 数据库临时文件：`*.db-shm`、`*.db-wal`
- 通用 SQLite 历史库：`*.sqlite`、`*.sqlite3`
- mihomo 下载数据和缓存：`Country.mmdb`、`GeoIP.dat`、`GeoSite.dat`、`cache.db`、`geoip.metadb`
- `ha-95598` 的调试截图、页面快照和临时登录二维码
- `infra-backup` 自己生成的 `logs/*` 和 `local-backups/*`

这类文件通常体积大、可再生成、变化频繁，或者不适合作为 Git 管理对象。需要时可以通过服务自身机制恢复，不应该进入日常配置备份。

## OpenWrt 要备份的文件

OpenWrt 不需要 clone 整个仓库。Pi 只把 `scripts/openwrt/` 中的运行脚本同步到 OpenWrt 的 `/root/infra-backup/`。

OpenWrt 备份内容包括：

- `sysupgrade -b` 官方备份包
- `/etc/config`
- `/etc/crontabs/root`
- `/root/*.sh`
- `/root/mihomo-*.sh`
- `/root/backup-*.sh`
- `iptables-save`
- `ip rule`
- table 100 路由
- `uci export`
- `opkg list-installed`

这些内容足够恢复路由器配置、定时任务、自定义脚本、策略路由和已安装软件清单。

## 不建议备份的东西

不要把这些东西加入 `BACKUP_PATHS`：

- 整个 `/home/pi`
- 整个 docker volume 目录
- Docker 镜像和容器层
- 下载目录、媒体库、前端构建产物
- 大型日志目录
- 可重新下载的 Geo 数据库
- 无恢复价值的缓存

备份策略是“少而关键”：只保留恢复服务需要的配置、小型状态和自定义脚本。

## 和 dotfiles 的边界

`dotfiles` 管用户级配置，例如 shell、git、ssh、chezmoi、用户自己的 ddns-go 配置模板。

`infra-backup` 管服务级和系统级恢复，例如 Docker compose、HA、MQTT、Zigbee2MQTT、network、systemd、cron、OpenWrt。

服务 `.env`、OpenWrt 私有配置、Pi 上的真实服务密钥不应该放进 `dotfiles`。

## 和 raspberry-conf 的边界

当前树莓派实际运行目录就是 `/home/pi`，并且 compose volume 指向 `$HOME/ha`、`$HOME/mosquitto`、`$HOME/zigbee2mqtt`。这个不要改成仓库内相对路径。

如果继续保留 `raspberry-conf`，它只能表达“树莓派当前服务栈配置长什么样”。但它容易和真实运行文件脱节，也容易把运行目录变成一个很脏的 Git worktree。

如果要降低维护成本，推荐方向是：

1. 保留 `infra-backup`。
2. 让 `infra-backup` 继续备份 `/home/pi` 当前真实文件。
3. 确认定时备份、远端上传、恢复验证都稳定。
4. 再删除或归档 `raspberry-conf`。

删除 `raspberry-conf` 前，至少确认最近一次 Pi 备份和恢复测试成功。
