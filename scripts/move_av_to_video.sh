#!/usr/bin/env bash
set -euo pipefail

# 从 115 网盘 云下载 和 tg/torrent 中提取 AV番号 视频，
# 重命名为 番号.mp4，移动到 /home/CloudDrive/115open/tg/video/AV/
#
# 用法:
#   ./scripts/move_av_to_video.sh          # dry-run 预演
#   ./scripts/move_av_to_video.sh --apply   # 正式执行

AV_DIR="/home/CloudDrive/115open/tg/video/AV"
SOURCES=(
  "/home/CloudDrive/115open/云下载"
  "/home/CloudDrive/115open/tg/torrent"
)

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

# AV番号正则: 2-6个大写字母 + 连字符 + 2-5位数字 + 可选后缀(-C, -UC, -U, -AI等)
# 大小写不敏感，脚本内部统一转大写
AV_REGEX='^[A-Z0-9]{2,6}-[0-9]{2,5}(-[A-Z0-9]+)?$'

# 标准化番号名：去掉前缀（avman.app_等）、去掉水印后缀、统一大写
normalize_bango() {
  local raw="$1"
  # 去掉 .mp4 后缀
  raw="${raw%.mp4}"
  # 去掉网站前缀 (avman.app_, hhd800.com@, 489155.com@ 等)
  raw="$(echo "$raw" | sed -E 's/^[a-zA-Z0-9._-]+[@_\.-]//')"
  # 去掉末尾的后缀版本差异
  raw="$(echo "$raw" | sed -E 's/[-_][A-Z0-9]+$//')"
  # 统一转大写
  echo "$raw" | tr '[:lower:]' '[:upper:]' | head -c 20
}

# 提取完整番号（保留后缀如 -C, -U, -AI）
# 从各种格式的字符串中提取 AV番号：用 grep 匹配番号模式
extract_full_bango() {
  local raw="$1"
  raw="${raw%.mp4}"
  # 转大写后用 grep 提取第一个番号模式
  local upper
  upper="$(echo "$raw" | tr '[:lower:]' '[:upper:]')"
  local result
  result="$(echo "$upper" | grep -oE '[A-Z0-9]{2,6}-[0-9]{2,5}(-[A-Z0-9]+)?' | head -1)"
  if [[ -n "$result" ]]; then
    echo "$result" | head -c 20
  else
    # fallback: 手动去掉已知前缀
    raw="$(echo "$upper" | sed -E 's/^[A-Z0-9._-]+@//')"
    raw="$(echo "$raw" | sed -E 's/^[A-Z0-9._]+\.APP_//')"
    raw="$(echo "$raw" | sed -E 's/^[A-Z0-9._-]+[_@\.-]//')"
    echo "$raw" | head -c 20
  fi
}

# 检测字符串是否为 AV番号 格式
is_av_bango() {
  [[ "$1" =~ $AV_REGEX ]]
}

# 找到一个目录下的主视频文件（按优先级）
find_main_video() {
  local dir="$1"
  local bango="$2"
  local candidates=()

  # 优先级 1: 文件名包含番号（去掉 hhd800.com@、489155.com@、avman.app_ 等前缀后匹配）
  while IFS= read -r -d '' f; do
    local base
    base="$(basename "$f")"
    local file_bango
    file_bango="$(extract_full_bango "$base")"
    if [[ "$file_bango" == "$bango" ]]; then
      echo "$f"
      return
    fi
  done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.ts" \) -print0 2>/dev/null)

  # 优先级 2: 最大的视频文件（跳过明显的小文件广告）
  local max_size=0
  local best=""
  while IFS= read -r -d '' f; do
    local size
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    # 跳过小于 50MB 的文件（很可能是广告/垃圾）
    if (( size < 52428800 )); then
      continue
    fi
    if (( size > max_size )); then
      max_size=$size
      best="$f"
    fi
  done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" \) -print0 2>/dev/null)
  echo "$best"
}

# 确保目标文件名不冲突
unique_dest() {
  local dir="$1"
  local name="$2"
  local base="${name%.*}"
  local ext="${name##*.}"
  local result="$dir/$name"
  local n=2
  while [[ -f "$result" ]]; do
    result="$dir/${base}_${n}.$ext"
    n=$((n + 1))
  done
  echo "$result"
}

main() {
  echo "=========================================="
  echo "AV番号 视频提取脚本"
  echo "模式: $($APPLY && echo "正式执行" || echo "预演 (dry-run)")"
  echo "=========================================="

  local total_found=0 total_moved=0 total_skipped=0 total_errors=0
  local dir dirname bango video sub_video ext new_name dest

  for src_root in "${SOURCES[@]}"; do
    [[ -d "$src_root" ]] || continue

    while IFS= read -r -d '' dir; do
      dirname="$(basename "$dir")"

      # 提取并转大写番号（处理 avman.app_、clot-015-C 等情况）
      bango="$(extract_full_bango "$dirname")"
      # 用大写版匹配正则
      is_av_bango "$bango" || continue

      total_found=$((total_found + 1))
      printf "\n[%s] %s\n" "$(basename "$src_root")" "$bango"

      video="$(find_main_video "$dir" "$bango")"
      if [[ -z "$video" ]]; then
        # 尝试子目录（像 KYMI-051.mp4/KYMI-051.mp4 这种结构）
        sub_video="$(find "$dir" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print 2>/dev/null | head -1)"
        if [[ -n "$sub_video" ]]; then
          video="$sub_video"
        fi
      fi

      if [[ -z "$video" ]]; then
        echo "  ⚠ 未找到视频文件，跳过"
        total_skipped=$((total_skipped + 1))
        continue
      fi

      ext="${video##*.}"
      new_name="${bango}.${ext,,}"
      dest="$(unique_dest "$AV_DIR" "$new_name")"

      echo "  源: $video"
      echo "  目标: $dest"

      if $APPLY; then
        mkdir -p "$AV_DIR"
        if mv -n "$video" "$dest" 2>/dev/null; then
          echo "  ✅ 移动成功"
          total_moved=$((total_moved + 1))
          # 清理空目录
          local parent_dir
          parent_dir="$(dirname "$video")"
          if [[ -d "$parent_dir" ]] && [[ -z "$(ls -A "$parent_dir" 2>/dev/null)" ]]; then
            rmdir "$parent_dir" 2>/dev/null && echo "  🧹 已清理空目录: $(basename "$parent_dir")"
          fi
        else
          echo "  ❌ 移动失败"
          total_errors=$((total_errors + 1))
        fi
      else
        echo "  → (预演，未操作)"
      fi
    done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  done

  echo ""
  echo "=========================================="
  echo "统计:"
  echo "  找到 AV番号: $total_found"
  echo "  移动成功: $total_moved"
  echo "  跳过: $total_skipped"
  echo "  错误: $total_errors"
  echo "=========================================="

  if ! $APPLY; then
    echo ""
    echo "预演模式，未做任何修改。确认无误后执行:"
    echo "  $0 --apply"
  fi
}

main
