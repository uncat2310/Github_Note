#!/usr/bin/env bash
set -euo pipefail

# 新机一键安装 + 恢复脚本
# 目标：在新机器上尽可能自动完成依赖安装、备份恢复、服务拉起和基础自检。
#
# 适用场景：
# 1) 你已经把 tg_media_parser_bot 的备份包传到新机（默认 /root/backups/tg_media_parser_bot_latest.tar.gz）
# 2) 你希望一条命令恢复机器人服务
#
# 用法：
#   bash new_machine_install_restore.sh
#   bash new_machine_install_restore.sh /root/tg_media_parser_bot_YYYYMMDD_HHMMSS.tar.gz
#   bash new_machine_install_restore.sh --archive /root/xxx.tar.gz --skip-install
#
# 参数：
#   --archive <path>   指定备份包路径
#   --skip-install     跳过 apt 依赖安装
#   --work-root <dir>  指定解压根目录（默认 /root）
#   -h|--help          显示帮助

ARCHIVE_PATH="/root/backups/tg_media_parser_bot_latest.tar.gz"
WORK_ROOT="/root"
SKIP_INSTALL=0

log() { echo "[new-restore] $*"; }
warn() { echo "[new-restore][warn] $*" >&2; }
die() { echo "[new-restore][error] $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
新机一键安装 + 恢复脚本

用法：
  bash new_machine_install_restore.sh
  bash new_machine_install_restore.sh /root/tg_media_parser_bot_YYYYMMDD_HHMMSS.tar.gz
  bash new_machine_install_restore.sh --archive /root/xxx.tar.gz --skip-install

参数：
  --archive <path>   指定备份包路径（默认 /root/backups/tg_media_parser_bot_latest.tar.gz）
  --skip-install     跳过 apt 依赖安装
  --work-root <dir>  指定解压根目录（默认 /root）
  -h|--help          显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || die "--archive 缺少路径参数"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --work-root)
      [[ $# -ge 2 ]] || die "--work-root 缺少目录参数"
      WORK_ROOT="$2"
      shift 2
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$1" == -* ]]; then
        die "未知参数: $1"
      fi
      ARCHIVE_PATH="$1"
      shift
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  die "请使用 root 运行此脚本。"
fi

PROJECT_DIR="${WORK_ROOT}/tg_media_parser_bot"
RUNTIME_DIR="${WORK_ROOT}/tg_media_parser_runtime"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  die "备份包不存在: ${ARCHIVE_PATH}"
fi

if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    log "安装基础依赖（python3/aria2/ffmpeg/qbittorrent/docker/rclone 等）"
    apt-get update -y
    apt-get install -y \
      ca-certificates \
      curl \
      tar \
      gzip \
      python3 \
      aria2 \
      ffmpeg \
      qbittorrent-nox \
      docker.io \
      rclone
  else
    warn "当前系统无 apt-get，跳过自动安装依赖，请手动安装。"
  fi
else
  log "已按参数跳过依赖安装"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker >/dev/null 2>&1 || true
fi

for cmd in python3 tar sha256sum systemctl; do
  command -v "${cmd}" >/dev/null 2>&1 || die "缺少命令: ${cmd}"
done

if ! command -v rclone >/dev/null 2>&1; then
  warn "未检测到 rclone，后续网盘上传/挂载相关功能会异常。"
fi
if [[ ! -x /usr/local/bin/clouddrive2 ]]; then
  warn "未检测到 /usr/local/bin/clouddrive2，可先恢复机器人，再手动补装 clouddrive2。"
fi

SHA_PATH="${ARCHIVE_PATH}.sha256"
if [[ -f "${SHA_PATH}" ]]; then
  log "校验备份完整性: ${SHA_PATH}"
  (cd "$(dirname "${ARCHIVE_PATH}")" && sha256sum -c "$(basename "${SHA_PATH}")")
else
  warn "未找到校验文件 ${SHA_PATH}，将继续恢复。"
fi

log "解压备份到 ${WORK_ROOT}"
tar -xzf "${ARCHIVE_PATH}" -C "${WORK_ROOT}"

[[ -d "${PROJECT_DIR}" ]] || die "解压后未发现项目目录: ${PROJECT_DIR}"

chmod +x "${PROJECT_DIR}/start.sh" || true
chmod +x "${PROJECT_DIR}/scripts/"*.sh 2>/dev/null || true

if [[ -d "${RUNTIME_DIR}/systemd" ]]; then
  log "恢复 systemd unit/timer 到 /etc/systemd/system"
  cp -f "${RUNTIME_DIR}/systemd/"*.service /etc/systemd/system/ 2>/dev/null || true
  cp -f "${RUNTIME_DIR}/systemd/"*.timer /etc/systemd/system/ 2>/dev/null || true
fi
if [[ -f "${RUNTIME_DIR}/rclone/rclone.conf" ]]; then
  log "恢复 rclone 配置到 /root/.config/rclone/rclone.conf"
  mkdir -p /root/.config/rclone
  cp -f "${RUNTIME_DIR}/rclone/rclone.conf" /root/.config/rclone/rclone.conf
  chmod 600 /root/.config/rclone/rclone.conf || true
fi

if [[ -d "${RUNTIME_DIR}/clouddrive2" ]]; then
  log "恢复 CloudDrive2 配置快照到 /root/Waytech/CloudDrive2"
  mkdir -p /root/Waytech/CloudDrive2
  cp -a "${RUNTIME_DIR}/clouddrive2/." /root/Waytech/CloudDrive2/
fi

systemctl daemon-reload

enable_now_if_exists() {
  local unit="$1"
  if systemctl list-unit-files | awk '{print $1}' | grep -qx "${unit}"; then
    log "启用并启动 ${unit}"
    systemctl enable --now "${unit}" || warn "${unit} 启动失败，请手动查看日志"
  else
    warn "未找到 unit: ${unit}（跳过）"
  fi
}

# 先拉起底层依赖服务
enable_now_if_exists "clouddrive2.service"
enable_now_if_exists "qbittorrent-nox.service"
enable_now_if_exists "rclone-123yunpan-webdav.service"
enable_now_if_exists "rclone-jgy-webdav.service"
enable_now_if_exists "telegram-bot-api-local.service"

# 再拉起机器人
if systemctl list-unit-files | awk '{print $1}' | grep -qx "tg-media-parser-bot.service"; then
  log "启用并重启 tg-media-parser-bot.service"
  systemctl enable tg-media-parser-bot.service || true
  systemctl restart tg-media-parser-bot.service
else
  die "缺少 tg-media-parser-bot.service，无法继续。"
fi

# 定时器（存在即启用）
for timer in \
  tg-media-parser-backup.timer \
  tg-media-parser-cache-clean.timer \
  tg-media-parser-offsite-backup.timer; do
  enable_now_if_exists "${timer}"
done

# 基础健康检查
BOT_STATUS="$(systemctl is-active tg-media-parser-bot.service || true)"
TGAPI_STATUS="$(systemctl is-active telegram-bot-api-local.service || true)"
CD2_STATUS="$(systemctl is-active clouddrive2.service || true)"
RCLONE_123_MOUNT_STATUS="$(systemctl is-active rclone-123yunpan-webdav.service || true)"
RCLONE_JGY_MOUNT_STATUS="$(systemctl is-active rclone-jgy-webdav.service || true)"

log "恢复完成，状态汇总："
echo "  tg-media-parser-bot.service       : ${BOT_STATUS}"
echo "  telegram-bot-api-local.service    : ${TGAPI_STATUS}"
echo "  clouddrive2.service               : ${CD2_STATUS}"
echo "  rclone-123yunpan-webdav.service   : ${RCLONE_123_MOUNT_STATUS}"
echo "  rclone-jgy-webdav.service         : ${RCLONE_JGY_MOUNT_STATUS}"

log "建议立刻执行："
echo "  systemctl status tg-media-parser-bot.service --no-pager -n 60"
echo "  tail -n 100 /root/tg_media_parser_bot/bot.log"
