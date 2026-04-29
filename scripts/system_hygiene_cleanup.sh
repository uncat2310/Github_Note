#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[system-hygiene]"

TMP_RETENTION_DAYS="${TMP_RETENTION_DAYS:-3}"
VAR_LOG_RETENTION_DAYS="${VAR_LOG_RETENTION_DAYS:-14}"
ROOT_CACHE_RETENTION_DAYS="${ROOT_CACHE_RETENTION_DAYS:-21}"
JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-250M}"
JOURNAL_MAX_AGE="${JOURNAL_MAX_AGE:-14d}"
ROOT_LOG_MAX_MB="${ROOT_LOG_MAX_MB:-80}"
ROOT_LOG_KEEP_LINES="${ROOT_LOG_KEEP_LINES:-5000}"
ENABLE_DOCKER_DANGLING_PRUNE="${ENABLE_DOCKER_DANGLING_PRUNE:-1}"
CD2_TEMP_DIR="${CD2_TEMP_DIR:-/root/Waytech/CloudDrive2/temp}"
CD2_FORCE_RESTART_ENABLED="${CD2_FORCE_RESTART_ENABLED:-1}"
CD2_FORCE_RESTART_THRESHOLD_GB="${CD2_FORCE_RESTART_THRESHOLD_GB:-8}"
CD2_FORCE_RESTART_COOLDOWN_MIN="${CD2_FORCE_RESTART_COOLDOWN_MIN:-360}"
CD2_MAINTENANCE_START_HOUR="${CD2_MAINTENANCE_START_HOUR:-2}"
CD2_MAINTENANCE_END_HOUR="${CD2_MAINTENANCE_END_HOUR:-6}"
CD2_LAST_FORCED_CLEANUP_FILE="${CD2_LAST_FORCED_CLEANUP_FILE:-/root/tg_media_parser_bot/.cd2_forced_cleanup_last_epoch}"
CD2_FORCE_RESTART_DISK_FULL_PERCENT="${CD2_FORCE_RESTART_DISK_FULL_PERCENT:-95}"
CD2_TRANSFER_SAMPLE_SEC="${CD2_TRANSFER_SAMPLE_SEC:-6}"
CD2_TRANSFER_ACTIVE_BYTES="${CD2_TRANSFER_ACTIVE_BYTES:-2097152}"
CD2_TRANSFER_RECENT_MMIN="${CD2_TRANSFER_RECENT_MMIN:-2}"

bytes_used_root() {
  df -B1 --output=used / | awk 'NR==2 {print $1}'
}

dir_size_bytes() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    du -sb "${path}" 2>/dev/null | awk '{print $1}'
  else
    echo 0
  fi
}

disk_used_percent_root() {
  df -P / | awk 'NR==2 {gsub("%","",$5); print $5}'
}

in_maintenance_window() {
  local current_hour_raw current_hour start_hour end_hour
  current_hour_raw="$(date '+%H')"
  current_hour=$(( 10#${current_hour_raw} ))
  start_hour=$(( 10#${CD2_MAINTENANCE_START_HOUR} ))
  end_hour=$(( 10#${CD2_MAINTENANCE_END_HOUR} ))

  if (( start_hour == end_hour )); then
    return 0
  fi

  if (( start_hour < end_hour )); then
    (( current_hour >= start_hour && current_hour < end_hour ))
  else
    (( current_hour >= start_hour || current_hour < end_hour ))
  fi
}

read_proc_io_bytes() {
  local pid="$1"
  local read_bytes write_bytes
  [[ -d "/proc/${pid}" ]] || {
    echo 0
    return 0
  }

  read_bytes="$(awk '/^read_bytes:/ {print $2}' "/proc/${pid}/io" 2>/dev/null || echo 0)"
  write_bytes="$(awk '/^write_bytes:/ {print $2}' "/proc/${pid}/io" 2>/dev/null || echo 0)"
  [[ -n "${read_bytes}" ]] || read_bytes=0
  [[ -n "${write_bytes}" ]] || write_bytes=0
  echo $(( read_bytes + write_bytes ))
}

collect_transfer_related_pids() {
  local main_pid child

  main_pid="$(systemctl show -p MainPID --value clouddrive2.service 2>/dev/null || true)"
  if [[ -n "${main_pid}" && "${main_pid}" != "0" ]]; then
    echo "${main_pid}"
    while IFS= read -r child; do
      [[ -n "${child}" ]] && echo "${child}"
    done < <(pgrep -P "${main_pid}" 2>/dev/null || true)
  fi

  for unit in rclone-123yunpan-webdav.service rclone-jgy-webdav.service; do
    main_pid="$(systemctl show -p MainPID --value "${unit}" 2>/dev/null || true)"
    if [[ -n "${main_pid}" && "${main_pid}" != "0" ]]; then
      echo "${main_pid}"
    fi
  done
}

rclone_transfer_process_active() {
  local transfer_lines
  transfer_lines="$(
    ps -eo pid,args --no-headers 2>/dev/null | awk '
      /(^|[[:space:]])rclone([[:space:]]|$)/ &&
      $0 !~ /(^|[[:space:]])rclone([[:space:]]+)mount([[:space:]]|$)/ &&
      $0 ~ /(^|[[:space:]])(copy|copyto|move|sync|rcat)([[:space:]]|$)/ {
        print $0
      }
    '
  )"
  if [[ -n "${transfer_lines}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && echo "${LOG_PREFIX} transfer_activity_detected reason=rclone_transfer_process cmd=${line}"
    done <<<"${transfer_lines}"
    return 0
  fi
  return 1
}

cd2_temp_recently_active() {
  [[ -d "${CD2_TEMP_DIR}" ]] || return 1
  find "${CD2_TEMP_DIR}" -maxdepth 1 -type f -mmin "-${CD2_TRANSFER_RECENT_MMIN}" -print -quit 2>/dev/null | grep -q .
}

transfer_activity_detected() {
  local pids_file sample_before sample_after pid io_before io_after io_delta
  sample_before=0
  sample_after=0

  if rclone_transfer_process_active; then
    return 0
  fi

  if cd2_temp_recently_active; then
    echo "${LOG_PREFIX} transfer_activity_detected reason=recent_temp_update within_mmin=${CD2_TRANSFER_RECENT_MMIN}"
    return 0
  fi

  pids_file="$(mktemp)"
  collect_transfer_related_pids | sort -u >"${pids_file}"
  if [[ ! -s "${pids_file}" ]]; then
    rm -f -- "${pids_file}"
    return 1
  fi

  while IFS= read -r pid; do
    io_before="$(read_proc_io_bytes "${pid}")"
    sample_before=$(( sample_before + io_before ))
  done <"${pids_file}"

  sleep "${CD2_TRANSFER_SAMPLE_SEC}"

  while IFS= read -r pid; do
    io_after="$(read_proc_io_bytes "${pid}")"
    sample_after=$(( sample_after + io_after ))
  done <"${pids_file}"

  rm -f -- "${pids_file}"
  io_delta=$(( sample_after - sample_before ))
  if (( io_delta < 0 )); then
    io_delta=0
  fi

  if (( io_delta >= CD2_TRANSFER_ACTIVE_BYTES )); then
    echo "${LOG_PREFIX} transfer_activity_detected reason=io_delta io_delta_bytes=${io_delta} threshold_bytes=${CD2_TRANSFER_ACTIVE_BYTES} sample_sec=${CD2_TRANSFER_SAMPLE_SEC}"
    return 0
  fi

  echo "${LOG_PREFIX} transfer_activity_idle io_delta_bytes=${io_delta} threshold_bytes=${CD2_TRANSFER_ACTIVE_BYTES} sample_sec=${CD2_TRANSFER_SAMPLE_SEC}"
  return 1
}

cd2_force_cleanup_cooldown_ready() {
  local now_epoch cooldown_sec last_epoch elapsed_sec
  now_epoch="$(date +%s)"
  cooldown_sec="$(( CD2_FORCE_RESTART_COOLDOWN_MIN * 60 ))"
  last_epoch=0

  if [[ -f "${CD2_LAST_FORCED_CLEANUP_FILE}" ]]; then
    last_epoch="$(tr -dc '0-9' <"${CD2_LAST_FORCED_CLEANUP_FILE}" | head -c 20)"
    [[ -n "${last_epoch}" ]] || last_epoch=0
  fi

  elapsed_sec="$(( now_epoch - last_epoch ))"
  if (( elapsed_sec < cooldown_sec )); then
    echo "${LOG_PREFIX} cd2_force_cleanup_cooldown active elapsed_sec=${elapsed_sec} cooldown_sec=${cooldown_sec}"
    return 1
  fi

  return 0
}

force_cleanup_cd2_temp() {
  local before_bytes after_bytes freed_bytes cleanup_rc
  local clouddrive2_active rclone_123_active rclone_jgy_active
  before_bytes="$(dir_size_bytes "${CD2_TEMP_DIR}")"
  cleanup_rc=0
  clouddrive2_active=0
  rclone_123_active=0
  rclone_jgy_active=0

  if systemctl is-active --quiet clouddrive2.service; then
    clouddrive2_active=1
  fi
  if systemctl is-active --quiet rclone-123yunpan-webdav.service; then
    rclone_123_active=1
  fi
  if systemctl is-active --quiet rclone-jgy-webdav.service; then
    rclone_jgy_active=1
  fi

  echo "${LOG_PREFIX} cd2_force_cleanup_begin before_bytes=${before_bytes} clouddrive2_active=${clouddrive2_active} rclone_123_active=${rclone_123_active} rclone_jgy_active=${rclone_jgy_active}"

  if (( rclone_123_active == 1 )); then
    systemctl stop rclone-123yunpan-webdav.service || true
  fi
  if (( rclone_jgy_active == 1 )); then
    systemctl stop rclone-jgy-webdav.service || true
  fi
  if (( clouddrive2_active == 1 )); then
    systemctl stop clouddrive2.service || true
  fi

  CRITICAL_WATERMARK_PERCENT=1 /root/tg_media_parser_bot/scripts/cleanup_bot_api_cache.sh || cleanup_rc=$?
  if (( cleanup_rc != 0 )); then
    echo "${LOG_PREFIX} cd2_force_cleanup_warning cleanup_script_rc=${cleanup_rc}"
  fi

  if (( clouddrive2_active == 1 )); then
    systemctl start clouddrive2.service || true
    sleep 2
  fi
  if (( rclone_123_active == 1 )); then
    systemctl start rclone-123yunpan-webdav.service || true
    sleep 1
  fi
  if (( rclone_jgy_active == 1 )); then
    systemctl start rclone-jgy-webdav.service || true
    sleep 1
  fi

  after_bytes="$(dir_size_bytes "${CD2_TEMP_DIR}")"
  freed_bytes="$(( before_bytes - after_bytes ))"
  if (( freed_bytes < 0 )); then
    freed_bytes=0
  fi
  date +%s >"${CD2_LAST_FORCED_CLEANUP_FILE}"
  echo "${LOG_PREFIX} cd2_force_cleanup_end after_bytes=${after_bytes} freed_bytes=${freed_bytes} cleanup_rc=${cleanup_rc}"
}

truncate_log_keep_tail() {
  local file_path="$1"
  local max_mb="$2"
  local keep_lines="$3"
  local size_bytes max_bytes tmp_file

  [[ -f "${file_path}" ]] || return 0

  size_bytes="$(stat -c %s "${file_path}" 2>/dev/null || echo 0)"
  max_bytes="$(( max_mb * 1024 * 1024 ))"
  if (( size_bytes <= max_bytes )); then
    return 0
  fi

  tmp_file="$(mktemp)"
  tail -n "${keep_lines}" "${file_path}" >"${tmp_file}" 2>/dev/null || true
  cat "${tmp_file}" >"${file_path}"
  rm -f -- "${tmp_file}"
  echo "${LOG_PREFIX} truncated_log path=${file_path} old_bytes=${size_bytes} keep_lines=${keep_lines}"
}

echo "${LOG_PREFIX} started at $(date '+%F %T')"
echo "${LOG_PREFIX} config tmp_days=${TMP_RETENTION_DAYS} var_log_days=${VAR_LOG_RETENTION_DAYS} cache_days=${ROOT_CACHE_RETENTION_DAYS} journal_size=${JOURNAL_MAX_SIZE} journal_age=${JOURNAL_MAX_AGE}"
echo "${LOG_PREFIX} cd2_force_config enabled=${CD2_FORCE_RESTART_ENABLED} threshold_gb=${CD2_FORCE_RESTART_THRESHOLD_GB} cooldown_min=${CD2_FORCE_RESTART_COOLDOWN_MIN} window=${CD2_MAINTENANCE_START_HOUR}-${CD2_MAINTENANCE_END_HOUR} disk_full_percent=${CD2_FORCE_RESTART_DISK_FULL_PERCENT} transfer_sample_sec=${CD2_TRANSFER_SAMPLE_SEC} transfer_active_bytes=${CD2_TRANSFER_ACTIVE_BYTES} transfer_recent_mmin=${CD2_TRANSFER_RECENT_MMIN}"

before_used_bytes="$(bytes_used_root)"

# 1) Clean temp directories and stale transient files.
if command -v systemd-tmpfiles >/dev/null 2>&1; then
  systemd-tmpfiles --clean >/dev/null 2>&1 || true
fi

tmp_mmin="$(( TMP_RETENTION_DAYS * 24 * 60 ))"
for tmp_dir in /tmp /var/tmp; do
  [[ -d "${tmp_dir}" ]] || continue
  find "${tmp_dir}" -xdev -mindepth 1 -mmin "+${tmp_mmin}" -print0 2>/dev/null | xargs -0r rm -rf -- 2>/dev/null || true
done

# 2) Keep system journal bounded.
if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time="${JOURNAL_MAX_AGE}" >/dev/null 2>&1 || true
  journalctl --vacuum-size="${JOURNAL_MAX_SIZE}" >/dev/null 2>&1 || true
fi

# 3) Remove old rotated logs.
if [[ -d /var/log ]]; then
  find /var/log -xdev -type f \( -name '*.gz' -o -regex '.*\.[0-9]+' -o -name '*.old' \) -mtime "+${VAR_LOG_RETENTION_DAYS}" -delete 2>/dev/null || true
fi

# 4) Keep frequently growing custom logs small.
for log_file in \
  /root/clouddrive2.log \
  /root/rclone-123yunpan-webdav.log \
  /root/rclone-jgy-webdav.log \
  /root/screenlog.0 \
  /root/tg_media_parser_bot/cache_cleanup.log \
  /root/tg_media_parser_bot/system_hygiene_cleanup.log
do
  truncate_log_keep_tail "${log_file}" "${ROOT_LOG_MAX_MB}" "${ROOT_LOG_KEEP_LINES}"
done

# 5) Clean package/cache leftovers.
if command -v apt-get >/dev/null 2>&1; then
  apt-get clean >/dev/null 2>&1 || true
  apt-get autoclean >/dev/null 2>&1 || true
fi

if [[ -d /root/.cache ]]; then
  find /root/.cache -xdev -type f -mtime "+${ROOT_CACHE_RETENTION_DAYS}" -delete 2>/dev/null || true
  find /root/.cache -xdev -type d -empty -delete 2>/dev/null || true
fi

if [[ -d /var/crash ]]; then
  find /var/crash -xdev -mindepth 1 -mtime +7 -delete 2>/dev/null || true
fi

if [[ -d /var/lib/systemd/coredump ]]; then
  find /var/lib/systemd/coredump -xdev -type f -mtime +7 -delete 2>/dev/null || true
fi

# 6) Clean dangling Docker build/image leftovers (safe subset only).
if [[ "${ENABLE_DOCKER_DANGLING_PRUNE}" == "1" ]] && command -v docker >/dev/null 2>&1; then
  docker image prune -f >/dev/null 2>&1 || true
  docker builder prune -f >/dev/null 2>&1 || true
fi

# 7) If CloudDrive2 temp grows beyond threshold, force-release busy files in off-peak window.
cd2_temp_before_force_bytes="$(dir_size_bytes "${CD2_TEMP_DIR}")"
cd2_temp_after_force_bytes="${cd2_temp_before_force_bytes}"
cd2_force_triggered=0
disk_used_percent="$(disk_used_percent_root)"
cd2_force_reason="none"

if [[ "${CD2_FORCE_RESTART_ENABLED}" == "1" ]]; then
  cd2_threshold_bytes="$(( CD2_FORCE_RESTART_THRESHOLD_GB * 1024 * 1024 * 1024 ))"
  if (( cd2_temp_before_force_bytes >= cd2_threshold_bytes )); then
    if (( disk_used_percent >= CD2_FORCE_RESTART_DISK_FULL_PERCENT )); then
      cd2_force_reason="disk_full_override"
      echo "${LOG_PREFIX} cd2_force_cleanup_override reason=disk_full disk_used_percent=${disk_used_percent} threshold_percent=${CD2_FORCE_RESTART_DISK_FULL_PERCENT}"
      force_cleanup_cd2_temp
      cd2_force_triggered=1
      cd2_temp_after_force_bytes="$(dir_size_bytes "${CD2_TEMP_DIR}")"
    elif ! in_maintenance_window; then
      cd2_force_reason="outside_window"
      echo "${LOG_PREFIX} cd2_force_cleanup_skipped reason=outside_window current_hour=$(date '+%H') window=${CD2_MAINTENANCE_START_HOUR}-${CD2_MAINTENANCE_END_HOUR}"
    elif ! cd2_force_cleanup_cooldown_ready; then
      cd2_force_reason="cooldown"
      echo "${LOG_PREFIX} cd2_force_cleanup_skipped reason=cooldown"
    elif transfer_activity_detected; then
      cd2_force_reason="transfer_active"
      echo "${LOG_PREFIX} cd2_force_cleanup_skipped reason=transfer_active disk_used_percent=${disk_used_percent} disk_full_threshold=${CD2_FORCE_RESTART_DISK_FULL_PERCENT}"
    else
      cd2_force_reason="scheduled_window"
      force_cleanup_cd2_temp
      cd2_force_triggered=1
      cd2_temp_after_force_bytes="$(dir_size_bytes "${CD2_TEMP_DIR}")"
    fi
  fi
fi

after_used_bytes="$(bytes_used_root)"
freed_bytes="$(( before_used_bytes - after_used_bytes ))"
if (( freed_bytes < 0 )); then
  freed_bytes=0
fi

echo "${LOG_PREFIX} before_used_bytes=${before_used_bytes} after_used_bytes=${after_used_bytes} freed_bytes=${freed_bytes}"
echo "${LOG_PREFIX} cd2_temp_before_force_bytes=${cd2_temp_before_force_bytes} cd2_temp_after_force_bytes=${cd2_temp_after_force_bytes} cd2_force_triggered=${cd2_force_triggered} cd2_force_reason=${cd2_force_reason} disk_used_percent=${disk_used_percent}"
echo "${LOG_PREFIX} finished at $(date '+%F %T')"
