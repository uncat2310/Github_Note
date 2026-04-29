#!/usr/bin/env bash
set -euo pipefail

# 一键恢复并启动 tg_media_parser_bot
# 用法：
#   bash oneclick_restore_from_backup.sh /root/tg_media_parser_bot_YYYYMMDD_HHMMSS.tar.gz
# 不传参数时，会自动尝试 /root/backups/tg_media_parser_bot_latest.tar.gz

ARCHIVE_PATH="${1:-/root/backups/tg_media_parser_bot_latest.tar.gz}"
WORK_ROOT="/root"
PROJECT_DIR="${WORK_ROOT}/tg_media_parser_bot"
RUNTIME_DIR="${WORK_ROOT}/tg_media_parser_runtime"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "[restore] backup archive not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

SHA_PATH="${ARCHIVE_PATH}.sha256"
if [[ -f "${SHA_PATH}" ]]; then
  echo "[restore] verifying checksum: ${SHA_PATH}"
  (cd "$(dirname "${ARCHIVE_PATH}")" && sha256sum -c "$(basename "${SHA_PATH}")")
else
  echo "[restore] checksum file not found, skip verification"
fi

echo "[restore] extracting archive: ${ARCHIVE_PATH}"
tar -xzf "${ARCHIVE_PATH}" -C "${WORK_ROOT}"

if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "[restore] project directory missing after extract: ${PROJECT_DIR}" >&2
  exit 1
fi

chmod +x "${PROJECT_DIR}/start.sh"
chmod +x "${PROJECT_DIR}/scripts"/*.sh || true

# 可选恢复运行时配置（service/timer + rclone）
if [[ -d "${RUNTIME_DIR}/systemd" ]]; then
  echo "[restore] restoring systemd units"
  cp -f "${RUNTIME_DIR}/systemd"/*.service /etc/systemd/system/ 2>/dev/null || true
  cp -f "${RUNTIME_DIR}/systemd"/*.timer /etc/systemd/system/ 2>/dev/null || true
fi
if [[ -f "${RUNTIME_DIR}/rclone/rclone.conf" ]]; then
  echo "[restore] restoring rclone config"
  mkdir -p /root/.config/rclone
  cp -f "${RUNTIME_DIR}/rclone/rclone.conf" /root/.config/rclone/rclone.conf
  chmod 600 /root/.config/rclone/rclone.conf || true
fi
if [[ -d "${RUNTIME_DIR}/clouddrive2" ]]; then
  echo "[restore] restoring CloudDrive2 config snapshot"
  mkdir -p /root/Waytech/CloudDrive2
  cp -a "${RUNTIME_DIR}/clouddrive2/." /root/Waytech/CloudDrive2/
fi

# 依赖安装（尽量幂等）
if command -v apt-get >/dev/null 2>&1; then
  echo "[restore] installing base dependencies (python3/aria2/ffmpeg/qbittorrent)"
  apt-get update -y || true
  apt-get install -y python3 aria2 ffmpeg qbittorrent-nox || true
fi

echo "[restore] reloading and enabling services"
systemctl daemon-reload

for unit in \
  clouddrive2.service \
  qbittorrent-nox.service \
  rclone-123yunpan-webdav.service \
  rclone-jgy-webdav.service \
  telegram-bot-api-local.service; do
  if systemctl list-unit-files | grep -q "^${unit}"; then
    systemctl enable --now "${unit}" || true
  fi
done

systemctl enable tg-media-parser-bot.service || true
systemctl restart tg-media-parser-bot.service

# 这些定时器按存在即启用
for unit in \
  tg-media-parser-backup.timer \
  tg-media-parser-cache-clean.timer \
  tg-media-parser-offsite-backup.timer; do
  if systemctl list-unit-files | grep -q "^${unit}"; then
    systemctl enable --now "${unit}" || true
  fi
done

echo "[restore] done"
systemctl --no-pager -l status tg-media-parser-bot.service | sed -n '1,24p'
