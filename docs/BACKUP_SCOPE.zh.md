# 备份范围和仓库职责

这份文档记录 `infra-backup` 当前按树莓派真实运行状态备份哪些文件、忽略哪些文件，以及它和 `dotfiles` 的边界。

## 结论

现在长期维护两个仓库：

- `dotfiles`：用户级配置，由 chezmoi 按设备应用。
- `infra-backup`：服务级和系统级恢复，按树莓派当前真实路径备份。

运行时配置继续放在树莓派实际路径，例如 `$HOME/apps/services/docker-compose.yml`、`$HOME/apps/services/ha/config`、`$HOME/network/docker-compose.yml`。`infra-backup` 负责把这些实际路径打包、验证、上传；它不保存被备份文件本身。

`dotfiles` 只管用户环境，不管服务栈私有配置、容器 volume、OpenWrt 私有配置和 restic 环境变量。

## 已执行验证

树莓派当前实际部署目录是 `$HOME/apps/ops/infra-backup`。日常验证命令：

```bash
cd ~/apps/ops/infra-backup
git pull --ff-only
cp config/backup.conf.example config/backup.conf
chmod 600 config/backup.conf
./scripts/02-backup-pi-local.sh
./restore/99-restore-test.sh
```

最近一次日常备份和清理日志在 `$BASE/logs`，本地 Pi 备份包在 `$BASE/local-backups/pi`。恢复测试通过时日志末尾会出现 `Restore test OK`。

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

- `$HOME/apps/services/docker-compose.yml`
- `$HOME/apps/services/.env`
- `$HOME/network/docker-compose.yml`
- `$HOME/network/.env`

这些文件决定服务栈如何启动，以及容器使用哪些环境变量。需要备份。

### 主 compose 里的其它服务状态

- `$HOME/network/cloudflared`
- `$HOME/apps/services/filebrowser/config`
- `$HOME/apps/services/filebrowser/database`
- `$HOME/apps/services/uptime-kuma/db-config.json`
- `$HOME/apps/services/uptime-kuma/kuma.db`

这些路径来自 `$HOME/network/docker-compose.yml` 和 `$HOME/apps/services/docker-compose.yml` 里的实际 volume。`cloudflared` 当前主要靠 `.env` 里的 token 启动，但保留目录可以覆盖以后切回本地配置文件的情况。Filebrowser 和 Uptime Kuma 的配置、数据库需要备份。

### Home Assistant

- `$HOME/apps/services/ha/Dockerfile.ha`
- `$HOME/apps/services/ha/config/configuration.yaml`
- `$HOME/apps/services/ha/config/secrets.yaml`
- `$HOME/apps/services/ha/config/automations.yaml`
- `$HOME/apps/services/ha/config/scripts.yaml`
- `$HOME/apps/services/ha/config/scenes.yaml`
- `$HOME/apps/services/ha/config/backups`

Home Assistant 的 YAML、密钥、自动化、脚本、场景都属于恢复核心。`backups` 目录也要保留，因为它能帮助从 HA 自己的备份中恢复集成和状态。

### Mosquitto

- `$HOME/apps/services/mosquitto/config`
- `$HOME/apps/services/mosquitto/data`

MQTT broker 的配置和持久数据需要备份，否则 Zigbee2MQTT、HA 和其它 MQTT 客户端恢复后可能连不上或状态丢失。

### Zigbee2MQTT

- `$HOME/apps/services/zigbee2mqtt/data/configuration.yaml`
- `$HOME/apps/services/zigbee2mqtt/data/coordinator_backup.json`
- `$HOME/apps/services/zigbee2mqtt/data/database.db`
- `$HOME/apps/services/zigbee2mqtt/data/state.json`
- `$HOME/apps/services/zigbee2mqtt/data/external_converters`

这些文件决定 Zigbee 网络、设备映射、协调器备份、设备状态和自定义转换器。需要备份。

### ddns-go

- `$HOME/network/ddns-go/.ddns_go_config.yaml`

树莓派上的 ddns-go 配置以这个实际路径为准。Mac 上的 ddns-go 配置不要覆盖这里。

### network 服务栈

- `$HOME/network/adguard/conf`
- `$HOME/network/wg-easy/data`
- `$HOME/network/mihomo/config/config.yaml`
- `$HOME/network/mihomo/config/proxies`
- `$HOME/network/mihomo/config/rules`
- `$HOME/network/caddy/Caddyfile`

这些文件决定 network compose、AdGuard Home 配置、WireGuard 配置、mihomo 规则和 Caddy 入口。需要备份。`$HOME/network/adguard/work` 当前体积较大，主要是运行数据和统计，不纳入默认关键配置备份。

### 不归 infra-backup 兜底的项目

- `$HOME/apps/projects/ha-95598`
- `$HOME/apps/projects/worldmonitor`
- `$HOME/Documents/Codex/...`

这些属于应用/项目源码或临时开发工作区。源码应该由各自 Git 仓库管理，运行数据是否备份要单独按项目决定。默认不把这些目录放进 `BACKUP_PATHS`，避免把项目源码、构建产物、调试截图和临时工作区混进基础设施备份。

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

- 整个 `$HOME`
- 整个 docker volume 目录
- Docker 镜像和容器层
- 下载目录、媒体库、前端构建产物
- 大型日志目录
- 可重新下载的 Geo 数据库
- 无恢复价值的缓存

备份策略是“少而关键”：只保留恢复服务需要的配置、小型状态和自定义脚本。

## 和 dotfiles 的边界

`dotfiles` 管用户级配置，例如 shell、git、ssh、chezmoi。

`infra-backup` 管服务级和系统级恢复，例如 Docker compose、HA、MQTT、Zigbee2MQTT、network、systemd、cron、OpenWrt。

服务 `.env`、OpenWrt 私有配置、Pi 上的真实服务密钥不应该放进 `dotfiles`。
