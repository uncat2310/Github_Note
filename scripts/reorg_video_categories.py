#!/usr/bin/env python3
"""
整理 tg/video 目录：合并单文件小目录、清理无意义目录名、按内容主题分类。
分类规则从 rules_config.py 共享读取，与 bot.py 保持一致。
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import time
from datetime import datetime

# 确保项目根目录在 sys.path 中，以便导入 scripts.rules_config
_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _BASE_DIR not in sys.path:
    sys.path.insert(0, _BASE_DIR)

from scripts.rules_config import (
    CATEGORY_RULES,
    MERGE_DIRS,
    RENAME_DIRS,
    ARCHIVE_DIRS,
    VALID_CATEGORIES,
)

VIDEO_DIR = "/home/CloudDrive/115open/tg/video"
DRY_RUN = "--apply" not in sys.argv

FILENAME_CLEAN_RE = re.compile(r'[\\/:*?"<>|]')
SENSITIVE_WORDS = [
    "489155.com@", "2048.cc-",
    "✅", "！", "？", "－", "【", "】",
    "，", "。", "、", "：", "；", "（", "）",
    "—", "～", " ", "  ", "​",
]

stats = {
    "dirs_merged": 0,
    "files_moved": 0,
    "dirs_renamed": 0,
    "files_renamed": 0,
    "errors": 0,
}

# 第二遍跳过的已分类目录 = 所有有效分类
SKIP_CATEGORIES = VALID_CATEGORIES | {"按时间归档", "视频", "视频2", "2048"}


def clean_filename(name: str) -> str:
    name = FILENAME_CLEAN_RE.sub("_", name)
    for word in SENSITIVE_WORDS:
        name = name.replace(word, "")
    name = name.strip("._- ")
    name = re.sub(r'[ _]+', '_', name)
    max_len = 80
    if len(name) > max_len:
        stem, ext = os.path.splitext(name)
        stem = stem[:max_len]
        name = stem + ext
    return name


def classify_by_name(dirname: str) -> str | None:
    lower = dirname.lower()
    for category, keywords in CATEGORY_RULES.items():
        for kw in keywords:
            if kw.lower() in lower:
                return category
    return None


def get_file_mtime(filepath: str) -> int:
    try:
        return int(os.path.getmtime(filepath))
    except OSError:
        return int(time.time())


def safe_move_file(src: str, dst_dir: str, new_name: str | None = None) -> bool:
    os.makedirs(dst_dir, exist_ok=True)
    filename = new_name or os.path.basename(src)
    dst = os.path.join(dst_dir, filename)
    if os.path.exists(dst):
        base, ext = os.path.splitext(filename)
        n = 2
        while os.path.exists(os.path.join(dst_dir, f"{base}_{n}{ext}")):
            n += 1
        dst = os.path.join(dst_dir, f"{base}_{n}{ext}")
    if DRY_RUN:
        print(f"    → {os.path.basename(dst_dir)}/{os.path.basename(dst)}")
        return True
    try:
        shutil.move(src, dst)
        return True
    except Exception as e:
        print(f"    ❌ {e}")
        stats["errors"] += 1
        return False


def process_archive_dir(dirpath: str, target_archive: str):
    dirname = os.path.basename(dirpath)
    # 递归收集所有文件（含子目录）
    files = []
    for root, _dirs, fnames in os.walk(dirpath):
        for f in fnames:
            files.append(os.path.join(root, f))
    if not files:
        return

    print(f"📦 {dirname}/ ({len(files)} files) → 按时间归档")
    for f in files:
        src = os.path.join(dirpath, f)
        mtime = get_file_mtime(src)
        ts = datetime.fromtimestamp(mtime).strftime("%Y%m%d_%H%M%S")
        ext = os.path.splitext(f)[1].lower() or ".mp4"
        new_name = f"{ts}{ext}"
        month_dir = datetime.fromtimestamp(mtime).strftime("%Y-%m")
        dst_dir = os.path.join(VIDEO_DIR, target_archive, month_dir)
        if safe_move_file(src, dst_dir, new_name):
            stats["files_moved"] += 1

    if not DRY_RUN:
        try:
            os.rmdir(dirpath)
            stats["dirs_merged"] += 1
        except:
            pass


def process_small_dir(dirpath: str):
    dirname = os.path.basename(dirpath)
    files = [f for f in os.listdir(dirpath) if os.path.isfile(os.path.join(dirpath, f))]
    if not files:
        return

    if dirname in MERGE_DIRS:
        target = MERGE_DIRS[dirname]
        print(f"📁 {dirname}/ → {target}/")
        for f in files:
            src = os.path.join(dirpath, f)
            dst_dir = os.path.join(VIDEO_DIR, target)
            if safe_move_file(src, dst_dir):
                stats["files_moved"] += 1
        if not DRY_RUN:
            try:
                os.rmdir(dirpath)
                stats["dirs_merged"] += 1
            except:
                pass
        return

    if dirname in RENAME_DIRS:
        new_name = RENAME_DIRS[dirname]
        new_path = os.path.join(VIDEO_DIR, new_name)
        if DRY_RUN:
            print(f"📁 {dirname}/ → {new_name}/")
        else:
            if not os.path.exists(new_path):
                os.rename(dirpath, new_path)
                stats["dirs_renamed"] += 1
                print(f"📁 {dirname}/ → {new_name}/ (已重命名)")
                return
            else:
                print(f"📁 {dirname}/ → {new_name}/ (合并)")
                for f in files:
                    src = os.path.join(dirpath, f)
                    if safe_move_file(src, new_path):
                        stats["files_moved"] += 1
                try:
                    os.rmdir(dirpath)
                    stats["dirs_merged"] += 1
                except:
                    pass
                return
        return

    category = classify_by_name(dirname)
    if category:
        if category == dirname:
            return
        print(f"📁 {dirname}/ ({len(files)} files) → {category}/")
        for f in files:
            src = os.path.join(dirpath, f)
            dst_dir = os.path.join(VIDEO_DIR, category)
            base, ext = os.path.splitext(f)
            clean_base = clean_filename(base)
            new_fname = f"{clean_base}{ext}" if clean_base else f
            if safe_move_file(src, dst_dir, new_fname):
                stats["files_moved"] += 1
        if not DRY_RUN:
            try:
                os.rmdir(dirpath)
                stats["dirs_merged"] += 1
            except:
                pass
    else:
        print(f"📁 {dirname}/ ({len(files)} files) → 按时间归档 (未分类)")
        for f in files:
            src = os.path.join(dirpath, f)
            mtime = get_file_mtime(src)
            ts = datetime.fromtimestamp(mtime).strftime("%Y%m%d_%H%M%S")
            ext = os.path.splitext(f)[1].lower() or ".mp4"
            new_name = f"{ts}{ext}"
            month_dir = datetime.fromtimestamp(mtime).strftime("%Y-%m")
            dst_dir = os.path.join(VIDEO_DIR, "按时间归档", month_dir)
            if safe_move_file(src, dst_dir, new_name):
                stats["files_moved"] += 1
        if not DRY_RUN:
            try:
                os.rmdir(dirpath)
                stats["dirs_merged"] += 1
            except:
                pass


def main():
    mode = "预演 (dry-run)" if DRY_RUN else "正式执行"
    print("=" * 60)
    print(f"tg/video 目录整理脚本")
    print(f"模式: {mode}")
    print("=" * 60)

    if not os.path.isdir(VIDEO_DIR):
        print(f"❌ 目录不存在: {VIDEO_DIR}")
        return 1

    entries = sorted([
        os.path.join(VIDEO_DIR, d)
        for d in os.listdir(VIDEO_DIR)
        if os.path.isdir(os.path.join(VIDEO_DIR, d))
        and not os.path.islink(os.path.join(VIDEO_DIR, d))
    ])

    for entry in entries:
        dirname = os.path.basename(entry)
        if dirname in ARCHIVE_DIRS:
            process_archive_dir(entry, "按时间归档")

    entries = sorted([
        os.path.join(VIDEO_DIR, d)
        for d in os.listdir(VIDEO_DIR)
        if os.path.isdir(os.path.join(VIDEO_DIR, d))
        and not os.path.islink(os.path.join(VIDEO_DIR, d))
        and d not in SKIP_CATEGORIES
    ])

    for entry in entries:
        dirname = os.path.basename(entry)
        if dirname in MERGE_DIRS or dirname in RENAME_DIRS:
            process_small_dir(entry)
            continue

        file_count = sum(1 for _ in os.listdir(entry) if os.path.isfile(os.path.join(entry, _)))
        if file_count <= 5:
            process_small_dir(entry)
        else:
            category = classify_by_name(dirname)
            if category and dirname != category:
                process_small_dir(entry)
            else:
                print(f"  ⏭ {dirname}/ ({file_count} files) — 保持")

    print(f"\n{'=' * 60}")
    print("清理空目录...")
    empty_count = 0
    for root, dirs, _ in os.walk(VIDEO_DIR, topdown=False):
        for d in dirs:
            dpath = os.path.join(root, d)
            try:
                if not os.listdir(dpath):
                    if not DRY_RUN:
                        os.rmdir(dpath)
                    empty_count += 1
            except:
                pass
    print(f"  空目录: {empty_count}")

    print(f"\n{'=' * 60}")
    print("统计:")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    print(f"{'=' * 60}")

    if DRY_RUN:
        print("\n⚠ 预演模式，未做修改。确认后执行:")
        print("  python3 scripts/reorg_video_categories.py --apply")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
