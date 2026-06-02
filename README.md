# infra-backup

树莓派和 OpenWrt 的轻量备份脚本。

## 原则

- 简单：纯 shell 脚本，不引入复杂调度系统。
- 少备：只备份关键配置和脚本，不备份缓存、日志、镜像、前端静态素材、历史数据库。
- 安全：本地备份包和日志默认用 `umask 077` 创建；R2 走 restic 加密。

## 部署位置

这个仓库部署在一台常开的 Linux 备份主机上，例如树莓派、家用服务器或 NAS。备份主机负责：

- 保存本项目代码、配置、日志和本地备份包
- 通过 SSH 触发 OpenWrt 备份
- 用 restic 把最新本地备份包上传到远端存储
- 用 cron 定时执行日常备份

OpenWrt 不部署完整仓库，只由备份主机同步 `scripts/openwrt/` 里的运行文件过去。

## 和其它仓库的关系

这几个仓库按职责分开，不是互相替代：

| 仓库 | 职责 | 例子 |
| --- | --- | --- |
| `dotfiles` | 管每台机器的用户级基础配置，由 chezmoi 应用。 | `.bashrc`、`.gitconfig` |
| `raspberry-conf` | 管树莓派当前服务栈的部署配置。 | `docker-compose.yml`、Home Assistant、Mosquitto、Zigbee2MQTT |
| `infra-backup` | 管备份流程，把树莓派和 OpenWrt 的关键状态打包并上传到远端。 | `scripts/02-backup-pi-local.sh`、restic、OpenWrt 备份脚本 |

简单说：

- `dotfiles` 负责“新机器怎么变成我的机器”。
- `raspberry-conf` 负责“树莓派上跑哪些服务，怎么跑”。
- `infra-backup` 负责“这些服务和路由器坏了以后怎么找回关键配置”。

所以 `infra-backup` 不应该合并进 `raspberry-conf`。它是备份工具，应该可以备份 `raspberry-conf` 产生的服务状态，但不应该成为服务运行目录本身。

## 目录

```text
infra-backup/
├── config/              # 主配置
├── scripts/             # 备份脚本
├── scripts/openwrt/     # 放到 OpenWrt 的脚本模板
├── logs/                # 日志
├── local-backups/       # 本地备份成品
└── restore/             # 恢复/验证脚本
```

本机私有配置不进仓库。首次使用：

```bash
cp config/backup.conf.example config/backup.conf
cp scripts/openwrt/config.env.example scripts/openwrt/config.env
```

OpenWrt 侧说明：

OpenWrt 不需要 clone 整个仓库，只需要在路由器上放一个很小的运行目录。执行下面命令会自动创建目录并同步文件：

```bash
./scripts/openwrt/upload-openwrt.sh
```

同步后，OpenWrt 上实际只有这些东西：

```text
/root/infra-backup/
├── backup-openwrt.sh   # 在路由器上执行备份
├── config.env          # 路由器侧私有配置：Pi 地址、目标目录、SSH key
└── logs/               # 路由器侧运行日志
```

日常备份时，Pi 会通过 SSH 执行 `/root/infra-backup/backup-openwrt.sh`，OpenWrt 生成 tar.gz 后再传回 Pi 的 `local-backups/openwrt/`。

## 备份内容

完整范围见 [docs/BACKUP_SCOPE.zh.md](docs/BACKUP_SCOPE.zh.md)。

树莓派本机备份范围在 `config/backup.conf` 的 `BACKUP_PATHS` 里配置，主要包括：

- `/home/pi` 当前真实服务栈的关键文件：
  - `$HOME/docker-compose.yml`
  - `$HOME/.env`
  - `$HOME/ha/Dockerfile.ha`
  - `$HOME/ha/config` 中的 YAML 配置、`secrets.yaml` 和 `backups`
  - `$HOME/mosquitto/config` 和 `$HOME/mosquitto/data`
  - `$HOME/zigbee2mqtt/data` 中的配置、协调器备份、设备数据库、运行状态和外部转换器
- `network` 服务栈的 compose、mihomo 主配置、代理和规则
- `caddy/config`
- 当前自定义 systemd service、docker proxy drop-in、cron、`/usr/local/bin` 下的自定义脚本
- ddns-go 配置

`infra-backup` 不要求被备份文件也在本仓库里。它的职责是记录备份/恢复流程，并把 `/home/pi` 当前真实运行文件打包。`raspberry-conf` 如果保留，只能作为历史 Git 投影；真正恢复以本备份为准。

默认排除：

- 日志、缓存、临时文件
- git、node_modules、pycache
- Home Assistant 历史数据库和 WAL/SHM
- clash 的 Geo 数据、缓存数据库
- 大量 Home Assistant 图片素材目录

OpenWrt 备份包括：

- `sysupgrade -b` 官方备份包
- `/etc/config`
- `/etc/crontabs/root`
- `/root/*.sh`、`mihomo-*.sh`、`backup-*.sh`
- `iptables-save`、`ip rule`、table 100 路由
- `uci export`、`opkg list-installed`

## 脚本

- `scripts/00-inventory.sh`：清点 systemd、cron、docker、compose、备份相关脚本。
- `scripts/01-backup-openwrt-pull.sh`：SSH 到 OpenWrt 执行备份并拉回 tar.gz。
- `scripts/02-backup-pi-local.sh`：把树莓派关键配置打成本地 tar.gz。
- `scripts/06-backup-all.sh`：把日常备份串起来，按顺序跑一遍。
- `scripts/07-install-cron.sh`：安装日常自动化 cron。
- `scripts/openwrt/upload-openwrt.sh`：把本地 `scripts/openwrt/` 下的 OpenWrt 原件同步到路由器。
- `scripts/03-restic-backup-r2.sh`：把最新本地 Pi / OpenWrt 备份上传到 R2 restic 仓库。
- `scripts/04-restic-check.sh`：检查 restic 仓库。
- `scripts/05-clean-local.sh`：本地只保留最近若干份备份。
- `restore/99-restore-test.sh`：解压最新本地 Pi 备份做恢复验证。

## 手动执行

```bash
./scripts/00-inventory.sh
./scripts/02-backup-pi-local.sh
./scripts/01-backup-openwrt-pull.sh
./scripts/03-restic-backup-r2.sh
./scripts/04-restic-check.sh
./scripts/05-clean-local.sh
./scripts/06-backup-all.sh
./scripts/07-install-cron.sh
```

日志在 `logs/`。本地备份在 `local-backups/pi/` 和 `local-backups/openwrt/`。

## 新增备份目录

只改 `config/backup.conf`：

- 加关键文件或小目录到 `BACKUP_PATHS`
- 大文件、缓存、数据库历史、图片素材加到 `EXCLUDE_PATHS`
- 不要把整个 `$HOME`、docker volume、下载目录、前端构建产物加入备份

## 注意

本地 tar.gz 不是加密格式，只靠文件权限保护；不要把 `local-backups/` 直接同步到不可信位置。
R2 每次只上传最新的 Pi/OpenWrt 本地备份包，restic 再按 `KEEP_DAILY`、`KEEP_WEEKLY`、`KEEP_MONTHLY` 保留快照；桶空了会自动重新初始化。
发布到 GitHub 前确认只提交 example 配置，不提交 `config/backup.conf`、`scripts/openwrt/config.env`、`logs/`、`local-backups/`。

自动化：

```bash
./scripts/07-install-cron.sh
```

每天 03:00 跑整套备份，周日 05:00 跑 restic check。
