#!/usr/bin/env bash
set -euo pipefail

# 备份项目根目录（源码 + 配置），用于迁移或灾备恢复。
PROJECT_DIR="/root/tg_media_parser_bot"
BACKUP_DIR="/root/backups"
PROJECT_NAME="tg_media_parser_bot"
# 仅保留最近 N 份时间戳备份，避免占满磁盘。
KEEP_COUNT="${KEEP_COUNT:-3}"

ts="$(date +%Y%m%d_%H%M%S)"
archive_ts="${BACKUP_DIR}/${PROJECT_NAME}_${ts}.tar.gz"
sha_ts="${archive_ts}.sha256"
archive_latest="${BACKUP_DIR}/${PROJECT_NAME}_latest.tar.gz"
sha_latest="${archive_latest}.sha256"

mkdir -p "${BACKUP_DIR}"
if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "Project dir not found: ${PROJECT_DIR}" >&2
  exit 1
fi

# 额外打包运行环境关键配置，避免迁移时丢失服务编排和 CloudDrive 配置。
runtime_stage="$(mktemp -d /tmp/tg_media_parser_runtime.XXXXXX)"
trap 'rm -rf "${runtime_stage}"' EXIT
runtime_root="${runtime_stage}/tg_media_parser_runtime"
mkdir -p "${runtime_root}/systemd" "${runtime_root}/clouddrive2" "${runtime_root}/claude_code" "${runtime_root}/codex"

for unit in \
  /etc/systemd/system/tg-media-parser-bot.service \
  /etc/systemd/system/tg-media-parser-backup.service \
  /etc/systemd/system/tg-media-parser-backup.timer \
  /etc/systemd/system/tg-media-parser-cache-clean.service \
  /etc/systemd/system/tg-media-parser-cache-clean.timer \
  /etc/systemd/system/clouddrive2-temp-clean.service \
  /etc/systemd/system/clouddrive2-temp-clean.timer \
  /etc/systemd/system/tg-media-parser-offsite-backup.service \
  /etc/systemd/system/tg-media-parser-offsite-backup.timer \
  /etc/systemd/system/telegram-bot-api-local.service \
  /etc/systemd/system/qbittorrent-nox.service \
  /etc/systemd/system/clouddrive2.service; do
  if [[ -f "${unit}" ]]; then
    cp -f "${unit}" "${runtime_root}/systemd/"
  fi
done

if [[ -d /root/Waytech/CloudDrive2 ]]; then
  # 只备份 CloudDrive2 配置/状态，不备份程序本体目录 /root/clouddrive2
  tar -C /root/Waytech/CloudDrive2 -cf - \
    --exclude='log' \
    --exclude='temp' \
    --exclude='*.log' \
    --exclude='file_buffer_cache' \
    . | tar -C "${runtime_root}/clouddrive2" -xf -
fi

# 备份 Claude Code 配置
if [[ -f /root/.claude/settings.json ]]; then
  mkdir -p "${runtime_root}/claude_code"
  cp -f /root/.claude/settings.json "${runtime_root}/claude_code/"
fi
if [[ -f /root/.claude.json ]]; then
  cp -f /root/.claude.json "${runtime_root}/claude_code/"
fi

# 备份 Codex 配置
if [[ -d /root/.codex ]]; then
  cp -rf /root/.codex/* "${runtime_root}/codex/" 2>/dev/null || true
fi

cat >"${runtime_root}/README.txt" <<'EOF'
这个目录是备份脚本自动附加的运行时配置快照：
1. systemd 服务/定时器文件（含主机器人、清理、异地备份、CloudDrive2、本地 TG Bot API）
2. CloudDrive2 配置快照（/root/Waytech/CloudDrive2，已排除 temp/log）
3. Claude Code 配置（~/.claude/settings.json 和 ~/.claude.json）
4. Codex 配置（~/.codex/）
恢复时可按需拷贝回原路径。
EOF

# 打包当前项目。排除日志、临时目录和缓存，减小体积并避免脏数据。
# 注意：这里按项目根目录整体打包，因此 scripts/ 下运维脚本（含 reclassify_tg_video_by_rules.py）会自动纳入备份。
# 本地 TG Bot API 的 bot_api_data 目录是运行缓存，不纳入备份。
tar -czf "${archive_ts}" \
  --exclude='tg_media_parser_bot/tmp' \
  --exclude='tg_media_parser_bot/bot.log' \
  --exclude='tg_media_parser_bot/bot_api_data' \
  --exclude='tg_media_parser_bot/__pycache__' \
  --exclude='tg_media_parser_bot/extractors/__pycache__' \
  --exclude='tg_media_parser_bot/tests/__pycache__' \
  --exclude='*.pyc' \
  -C /root tg_media_parser_bot \
  -C "${runtime_stage}" tg_media_parser_runtime

# 为时间戳包生成校验文件，并同步覆盖 latest 快照。
sha256sum "${archive_ts}" > "${sha_ts}"
cp -f "${archive_ts}" "${archive_latest}"
sha256sum "${archive_latest}" > "${sha_latest}"

# 立即校验 latest 备份可读性，失败时脚本会退出并报错。
sha256sum -c "${sha_latest}" >/dev/null

# Keep only latest N timestamped backups and their checksum files.
mapfile -t timestamped_archives < <(
  ls -1t "${BACKUP_DIR}/${PROJECT_NAME}"_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].tar.gz 2>/dev/null || true
)

# 清理不完整备份（无 .sha256，通常是中断留下的半包）
for archive in "${timestamped_archives[@]}"; do
  if [[ ! -f "${archive}.sha256" ]]; then
    rm -f "${archive}"
  fi
done

mapfile -t timestamped_archives < <(
  ls -1t "${BACKUP_DIR}/${PROJECT_NAME}"_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].tar.gz 2>/dev/null || true
)

if ((${#timestamped_archives[@]} > KEEP_COUNT)); then
  for old_archive in "${timestamped_archives[@]:KEEP_COUNT}"; do
    rm -f "${old_archive}" "${old_archive}.sha256"
  done
fi

echo "Backup done."
echo "timestamped: ${archive_ts}"
echo "latest:      ${archive_latest}"
echo "sha256:      ${sha_latest}"
echo "retained timestamped backups: ${KEEP_COUNT}"
