#!/usr/bin/env python3
"""
全量重分类/重命名脚本（面向 /home/CloudDrive/115open/tg/video）。

设计目标：
1. 与 bot.py 当前在线规则保持一致（调用 MediaParserBot 内部分类与命名函数）。
2. 人工/AI 都能安全执行（默认 dry-run，不会改动文件）。
3. 操作可追溯（每次执行写入 JSON 日志）。
4. 可选清理空目录（默认开启）。

使用示例：
1. 预演（不改文件）：
   python3 scripts/reclassify_tg_video_by_rules.py --dry-run
2. 正式执行：
   python3 scripts/reclassify_tg_video_by_rules.py --apply
3. 指定根目录：
   python3 scripts/reclassify_tg_video_by_rules.py --apply --root /home/CloudDrive/115open/tg/video
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass, asdict
from types import SimpleNamespace
from typing import Dict, List, Tuple

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from bot import MediaParserBot


# 只处理视频扩展名；和主程序保持一致。
VIDEO_EXTS = {
    ".mp4",
    ".mov",
    ".mkv",
    ".webm",
    ".m4v",
    ".avi",
    ".wmv",
    ".flv",
    ".ts",
    ".m2ts",
}


@dataclass
class ChangeItem:
    src: str
    dst: str
    forced_tag: str
    primary_tag: str
    keyword: str


def build_bot_for_offline_classify() -> MediaParserBot:
    """
    构造一个最小可用的 MediaParserBot 实例。

    注意：
    - 这里只需要分类/命名函数，不需要启动 Telegram 网络交互。
    - 因此使用 object.__new__ 跳过 __init__，并仅注入必要 settings。
    """
    bot = object.__new__(MediaParserBot)
    bot.settings = SimpleNamespace(
        forward_video_download_dir="/home/CloudDrive/115open/tg",
        local_upload_root="/home/CloudDrive/115open/tg",
    )
    return bot


def iter_video_files(root: str) -> List[str]:
    files: List[str] = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for file_name in filenames:
            if os.path.splitext(file_name)[1].lower() in VIDEO_EXTS:
                files.append(os.path.join(dirpath, file_name))
    files.sort()
    return files


def compute_target(bot: MediaParserBot, root: str, src_path: str) -> Tuple[str, str, str, str]:
    """
    计算单个文件的目标路径，不执行任何写操作。

    返回：
    - dst_path: 目标绝对路径
    - forced_tag: 强规则命中的分类（若无则空）
    - primary_tag: 最终分类目录名
    - keyword: 最终文件名关键词
    """
    file_name = os.path.basename(src_path)
    mtime = int(os.path.getmtime(src_path) or time.time())
    message = {"date": mtime, "message_id": 0}

    tags, keyword = bot._extract_video_tags_and_keyword("", file_name)
    primary_tag = bot._resource_primary_tag(tags, "video", default="未分类")
    forced_tag = bot._detect_forced_primary_tag(
        caption_text=os.path.relpath(src_path, root),
        file_name=file_name,
        keyword=keyword,
        tags=tags,
    )
    if forced_tag:
        primary_tag = forced_tag
    primary_tag = bot._aggregate_primary_tag(primary_tag, keyword=keyword, file_name=file_name)
    primary_tag = bot._apply_animation_series_primary_tag(
        primary_tag,
        keyword=keyword,
        file_name=file_name,
        caption_text=os.path.relpath(src_path, root),
    )

    if keyword == "未命名":
        stem = os.path.splitext(file_name)[0]
        keyword = bot._safe_storage_name(stem, max_len=48) or "未命名"

    suffix = os.path.splitext(file_name)[1].lower() or ".mp4"
    final_name = bot._build_forward_item_filename(
        media_kind="video",
        keyword=keyword,
        index=1,
        suffix=suffix,
        original_name=file_name,
        message=message,
        primary_tag=primary_tag,
    )
    target_dir, _remote_root = bot._forward_storage_roots("video", primary_tag, message)
    return os.path.join(target_dir, final_name), forced_tag, primary_tag, keyword


def ensure_unique_destination(bot: MediaParserBot, src_path: str, dst_path: str) -> str:
    """
    若目标文件已存在，生成不冲突目标名。

    规则：
    - 与 bot 内一致，使用 _ensure_unique_filename；
    - 文件名主体仍限制在 20 字符以内（视频规则）。
    """
    if not os.path.exists(dst_path):
        return dst_path
    dst_dir = os.path.dirname(dst_path)
    dst_name = os.path.basename(dst_path)
    unique_name = bot._ensure_unique_filename(dst_dir, dst_name, max_stem_len=20)
    return os.path.join(dst_dir, unique_name)


def prune_empty_dirs(root: str, apply: bool) -> List[str]:
    removed: List[str] = []
    for dirpath, _dirnames, _filenames in os.walk(root, topdown=False):
        if os.path.abspath(dirpath) == os.path.abspath(root):
            continue
        try:
            if os.listdir(dirpath):
                continue
            if apply:
                os.rmdir(dirpath)
            removed.append(dirpath)
        except Exception:
            continue
    return removed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="按 bot.py 当前规则重分类 /tg/video 文件。默认 dry-run，不改文件。"
    )
    parser.add_argument("--root", default="/home/CloudDrive/115open/tg/video", help="视频根目录（默认 /home/CloudDrive/115open/tg/video）")
    parser.add_argument("--dry-run", action="store_true", help="仅预演，不改文件（默认行为）")
    parser.add_argument("--apply", action="store_true", help="正式执行移动/重命名")
    parser.add_argument("--no-prune-empty", action="store_true", help="执行后不清理空目录")
    args = parser.parse_args()

    # 执行语义：
    # - 传 --apply 才真正修改；
    # - 仅传 --dry-run 或不传都为预演。
    apply = bool(args.apply)

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        raise SystemExit(f"root not found: {root}")

    bot = build_bot_for_offline_classify()
    files = iter_video_files(root)

    changes: List[ChangeItem] = []
    unchanged = 0
    errors: List[Dict[str, str]] = []

    for src in files:
        try:
            dst, forced_tag, primary_tag, keyword = compute_target(bot, root, src)
            src_abs = os.path.abspath(src)
            dst_abs = os.path.abspath(dst)
            if src_abs == dst_abs:
                unchanged += 1
                continue

            os.makedirs(os.path.dirname(dst_abs), exist_ok=True)
            final_dst = ensure_unique_destination(bot, src_abs, dst_abs)
            if os.path.abspath(final_dst) == src_abs:
                unchanged += 1
                continue

            if apply:
                os.replace(src_abs, final_dst)

            changes.append(
                ChangeItem(
                    src=src_abs,
                    dst=os.path.abspath(final_dst),
                    forced_tag=forced_tag,
                    primary_tag=primary_tag,
                    keyword=keyword,
                )
            )
        except Exception as exc:
            errors.append({"file": src, "error": str(exc)})

    removed_empty_dirs: List[str] = []
    if not args.no_prune_empty:
        removed_empty_dirs = prune_empty_dirs(root, apply=apply)

    mode = "apply" if apply else "dry_run"
    ts = time.strftime("%Y%m%d_%H%M%S", time.localtime())
    log_path = f"/root/tg_media_parser_bot/data/reclassify_tg_video_{mode}_{ts}.json"
    payload = {
        "mode": mode,
        "root": root,
        "processed": len(files),
        "changed": len(changes),
        "unchanged": unchanged,
        "errors": errors,
        "removed_empty_dirs": removed_empty_dirs,
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
        "changes": [asdict(item) for item in changes],
    }
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)

    print(f"MODE={mode}")
    print(f"ROOT={root}")
    print(f"PROCESSED={len(files)}")
    print(f"CHANGED={len(changes)}")
    print(f"UNCHANGED={unchanged}")
    print(f"ERRORS={len(errors)}")
    print(f"REMOVED_EMPTY_DIRS={len(removed_empty_dirs)}")
    print(f"LOG={log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
