#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/root/tg_media_parser_bot"
BACKUP_DIR="/root/backups"
PROJECT_NAME="tg_media_parser_bot"
REMOTE_DIR="${OFFSITE_BACKUP_LOCAL_DIR:-/home/CloudDrive/百度网盘/备份/tg_media_parser_bot_backups}"
KEEP_REMOTE_COUNT="${KEEP_REMOTE_COUNT:-2}"

echo "[offsite-backup] started at $(date '+%F %T')"

cd "${PROJECT_DIR}"
"${PROJECT_DIR}/scripts/backup_replace.sh"

latest_archive="$(ls -1t "${BACKUP_DIR}/${PROJECT_NAME}"_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].tar.gz | head -n1)"
latest_sha="${latest_archive}.sha256"
archive_name="$(basename "${latest_archive}")"
sha_name="$(basename "${latest_sha}")"

if [[ ! -f "${latest_archive}" || ! -f "${latest_sha}" ]]; then
  echo "[offsite-backup] latest archive not found after local backup" >&2
  exit 1
fi

mkdir -p "${REMOTE_DIR}"
cp -f "${latest_archive}" "${REMOTE_DIR}/${archive_name}"
cp -f "${latest_sha}" "${REMOTE_DIR}/${sha_name}"
echo "[offsite-backup] copied: ${archive_name}"

mapfile -t remote_archives < <(
  find "${REMOTE_DIR}" -maxdepth 1 -type f -name "${PROJECT_NAME}_????????_??????.tar.gz" -printf '%f\n' \
    | sort -r
)

if ((${#remote_archives[@]} > KEEP_REMOTE_COUNT)); then
  for old_name in "${remote_archives[@]:KEEP_REMOTE_COUNT}"; do
    rm -f "${REMOTE_DIR}/${old_name}" || true
    rm -f "${REMOTE_DIR}/${old_name}.sha256" || true
    echo "[offsite-backup] pruned: ${old_name}"
  done
fi

echo "[offsite-backup] keep_remote_count=${KEEP_REMOTE_COUNT}"
echo "[offsite-backup] finished at $(date '+%F %T')"
