#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import sys
import time
from typing import Dict, List, Tuple

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from bot import ARCHIVE_IMAGE_EXTENSIONS, ARCHIVE_VIDEO_EXTENSIONS, MediaParserBot


DEFAULT_SOURCE_DIRS = (
    "/home/CloudDrive/115open/接收",
    "/home/CloudDrive/115open/最近接收",
)
SKIP_FILE_NAMES = {".DS_Store", "Thumbs.db"}
SKIP_DIR_NAMES = {"__MACOSX"}
TEMP_NAME_MARKERS = (".tmp-",)
TEMP_SUFFIXES = (".part", ".aria2", ".crdownload", ".download", ".partial", ".tmp")
GENERIC_CONTEXT_NAMES = {
    "",
    "接收",
    "最近接收",
    "待整理",
    "av",
    "video",
    "videos",
    "photo",
    "photos",
    "image",
    "images",
    "file",
    "files",
}
KNOWN_SUFFIX_EXTENSIONS = set(ARCHIVE_VIDEO_EXTENSIONS + ARCHIVE_IMAGE_EXTENSIONS + (
    ".zip",
    ".rar",
    ".7z",
    ".tar",
    ".gz",
    ".bz2",
    ".xz",
    ".pdf",
    ".txt",
    ".doc",
    ".docx",
    ".srt",
    ".ass",
    ".mp3",
    ".wav",
    ".flac",
))


def _archive_sort_key(value: str):
    parts = re.split(r"(\d+)", str(value or ""))
    return [int(part) if part.isdigit() else part.lower() for part in parts]


def _is_temp_path(path: str) -> bool:
    lowered = str(path or "").lower()
    if any(marker in lowered for marker in TEMP_NAME_MARKERS):
        return True
    return lowered.endswith(TEMP_SUFFIXES)


def _ensure_unique_path(path: str) -> str:
    if not os.path.exists(path):
        return path
    parent = os.path.dirname(path)
    name = os.path.basename(path)
    stem, ext = os.path.splitext(name)
    counter = 2
    while True:
        candidate = os.path.join(parent, f"{stem}_{counter}{ext}")
        if not os.path.exists(candidate):
            return candidate
        counter += 1


def _prune_empty_dirs(root: str) -> None:
    if not os.path.isdir(root):
        return
    for current_root, dirs, files in os.walk(root, topdown=False):
        if current_root == root:
            continue
        if dirs or files:
            continue
        try:
            os.rmdir(current_root)
        except OSError:
            pass


def _looks_generic_name(value: str) -> bool:
    raw_value = str(value or "").strip().lower()
    normalized = re.sub(r"[\W_]+", "", str(value or ""), flags=re.UNICODE).lower()
    if not normalized:
        return True
    if raw_value.startswith(("from_", "from-", "telegram_", "telegram-")):
        return True
    if raw_value.startswith("video_") and re.search(r"(19|20)\d{2}", raw_value):
        return True
    if raw_value.startswith(("telegram", "from")) and "aqad" in raw_value:
        return True
    if normalized in {"v", "mv", "video", "photo", "img", "image", "file", "p"}:
        return True
    if re.fullmatch(r"(?:img|image|photo|video|v|mv|file|p)?\d+", normalized):
        return True
    if re.fullmatch(r"\d{1,6}", normalized):
        return True
    return False


def _extract_numeric_hint(value: str) -> str:
    matches = re.findall(r"\d+", str(value or ""))
    if not matches:
        return ""
    hint = matches[-1].lstrip("0")
    return hint or "0"


def _default_extension(file_name: str, media_kind: str) -> str:
    ext = os.path.splitext(file_name or "")[1].lower()
    if ext:
        return ext
    return {"video": ".mp4", "photo": ".jpg", "file": ".bin"}.get(media_kind, ".bin")


def _clean_file_stem(bot: MediaParserBot, stem: str, max_len: int) -> str:
    text = str(stem or "").strip()
    text = text.lstrip("#@")
    text = re.sub(r"^[A-Za-z]?@", "", text)
    text = re.sub(r"^from[-_ ]+", "", text, flags=re.IGNORECASE)
    text = bot._strip_resource_noise(text, keep_brackets=False)
    return bot._safe_storage_name(text, max_len=max_len)


def _clean_context_part(bot: MediaParserBot, raw: str, max_len: int = 72) -> str:
    text = str(raw or "").strip()
    if not text:
        return ""
    text = text.lstrip("#@")
    stem, ext = os.path.splitext(text)
    if stem and ext.lower() in KNOWN_SUFFIX_EXTENSIONS:
        text = stem
    text = re.sub(r"^from[-_ ]+", "", text, flags=re.IGNORECASE)
    text = bot._strip_resource_noise(text, keep_brackets=False)
    cleaned = bot._safe_storage_name(text, max_len=max_len)
    if not cleaned:
        return ""
    cleaned = re.sub(r"^(?:B站|b站)[_ -]+", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^(?:AV|av)(?:[_ -]+|$)", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^(?:待整理)(?:[_ -]+|$)", "", cleaned)
    cleaned = bot._safe_storage_name(cleaned, max_len=max_len)
    if not cleaned:
        return ""
    if cleaned.lower() in GENERIC_CONTEXT_NAMES:
        return ""
    return cleaned


def _context_parts(bot: MediaParserBot, source_root: str, current_root: str) -> List[str]:
    relative = os.path.relpath(current_root, source_root)
    if relative in {".", ""}:
        return []
    parts = []
    for raw_part in relative.split(os.sep):
        cleaned = _clean_context_part(bot, raw_part)
        if not cleaned:
            continue
        if parts and parts[-1] == cleaned:
            continue
        parts.append(cleaned)
    return parts


def _media_kind_for_name(file_name: str) -> str:
    ext = os.path.splitext(file_name or "")[1].lower()
    if ext in ARCHIVE_VIDEO_EXTENSIONS:
        return "video"
    if ext in ARCHIVE_IMAGE_EXTENSIONS:
        return "photo"
    return "file"


def _fallback_primary_tag(bot: MediaParserBot, file_name: str, media_kind: str) -> str:
    raw_stem = os.path.splitext(file_name or "")[0]
    hash_tags = re.findall(r"#([^\s#_]+)", raw_stem)
    for candidate in hash_tags:
        cleaned = bot._normalize_resource_tag(candidate, max_len=32)
        if cleaned and not _looks_generic_name(cleaned):
            return cleaned

    prefix_candidates = [
        raw_stem.split("_", 1)[0],
        raw_stem.split("丨", 1)[0],
        raw_stem.split("|", 1)[0],
        raw_stem.split("【", 1)[0],
        raw_stem.split("[", 1)[0],
        raw_stem.split("(", 1)[0],
    ]
    for candidate in prefix_candidates:
        cleaned = bot._normalize_resource_tag(bot._strip_resource_noise(candidate, keep_brackets=False), max_len=32)
        if cleaned and not _looks_generic_name(cleaned):
            return cleaned

    tags, keyword = bot._extract_video_tags_and_keyword("", file_name)
    default_tag = "视频" if media_kind == "video" else "未分类"
    primary = bot._resource_primary_tag(tags, media_kind, default=default_tag)
    if primary == default_tag:
        keyword_tag = bot._normalize_resource_tag(keyword, max_len=32)
        if keyword_tag and not _looks_generic_name(keyword_tag):
            primary = keyword_tag
    return bot._safe_storage_name(primary, max_len=32) or default_tag


def _select_primary_tag(bot: MediaParserBot, context_parts: List[str], file_name: str, media_kind: str) -> str:
    for part in context_parts:
        normalized = bot._normalize_resource_tag(part, max_len=32)
        if normalized:
            return normalized
    return _fallback_primary_tag(bot, file_name, media_kind)


def _select_collection_name(bot: MediaParserBot, context_parts: List[str], primary_tag: str) -> str:
    for part in reversed(context_parts):
        cleaned = bot._safe_storage_name(bot._extract_resource_keyword(part), max_len=72)
        if not cleaned or cleaned == primary_tag:
            continue
        return cleaned
    return ""


def _build_photo_name(
    bot: MediaParserBot,
    file_name: str,
    primary_tag: str,
    index: int,
    total: int,
    collection_name: str,
) -> str:
    stem = os.path.splitext(file_name or "")[0]
    ext = _default_extension(file_name, "photo")
    cleaned = _clean_file_stem(bot, stem, max_len=64)
    if cleaned and not _looks_generic_name(cleaned):
        return cleaned + ext
    if total > 1:
        return f"{index:03d}{ext}"
    hint = _extract_numeric_hint(stem)
    if hint:
        return f"{int(hint):03d}{ext}"
    base = bot._safe_storage_name(collection_name, max_len=48) or bot._safe_storage_name(primary_tag, max_len=48) or "photo"
    return base + ext


def _build_media_name(
    bot: MediaParserBot,
    file_name: str,
    media_kind: str,
    primary_tag: str,
    collection_name: str,
    index: int,
    total: int,
) -> str:
    stem = os.path.splitext(file_name or "")[0]
    ext = _default_extension(file_name, media_kind)
    cleaned = _clean_file_stem(bot, stem, max_len=72)
    if cleaned and not _looks_generic_name(cleaned):
        return cleaned + ext

    base = (
        bot._safe_storage_name(collection_name, max_len=56)
        or bot._safe_storage_name(primary_tag, max_len=32)
        or media_kind
    )
    hint = _extract_numeric_hint(stem)
    if hint:
        return f"{base}_{hint}{ext}"
    if total > 1:
        return f"{base}_{index:02d}{ext}"
    return base + ext


def _move_file(source_path: str, target_path: str, dry_run: bool = False) -> None:
    if dry_run:
        return
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    try:
        os.replace(source_path, target_path)
        return
    except Exception:
        pass
    try:
        shutil.copy2(source_path, target_path)
        os.remove(source_path)
    except Exception:
        try:
            if os.path.exists(target_path):
                os.remove(target_path)
        except OSError:
            pass
        raise


def _process_directory(
    bot: MediaParserBot,
    source_root: str,
    current_root: str,
    files: List[str],
    log_entries: List[Dict],
    summary: Dict,
    dry_run: bool = False,
) -> None:
    visible_files = []
    for file_name in sorted(files, key=_archive_sort_key):
        if file_name in SKIP_FILE_NAMES or file_name.startswith("."):
            continue
        source_path = os.path.join(current_root, file_name)
        if _is_temp_path(source_path):
            summary["totals"]["skipped"] += 1
            summary["sources"][source_root]["skipped"] += 1
            continue
        if not os.path.isfile(source_path):
            continue
        visible_files.append(file_name)
    if not visible_files:
        return

    context_parts = _context_parts(bot, source_root, current_root)
    totals_by_kind = {"video": 0, "photo": 0, "file": 0}
    for file_name in visible_files:
        totals_by_kind[_media_kind_for_name(file_name)] += 1

    indexes = {"video": 0, "photo": 0, "file": 0}
    for file_name in visible_files:
        source_path = os.path.join(current_root, file_name)
        media_kind = _media_kind_for_name(file_name)
        indexes[media_kind] += 1

        primary_tag = _select_primary_tag(bot, context_parts, file_name, media_kind)
        collection_name = _select_collection_name(bot, context_parts, primary_tag)
        _local_root, target_root = bot._forward_storage_roots(
            media_kind,
            primary_tag,
            {"date": os.path.getmtime(source_path)},
        )
        if media_kind == "photo" and collection_name:
            target_root = os.path.join(target_root, collection_name)

        if media_kind == "photo":
            target_name = _build_photo_name(
                bot,
                file_name,
                primary_tag,
                indexes[media_kind],
                totals_by_kind[media_kind],
                collection_name,
            )
        else:
            target_name = _build_media_name(
                bot,
                file_name,
                media_kind,
                primary_tag,
                collection_name,
                indexes[media_kind],
                totals_by_kind[media_kind],
            )

        target_path = _ensure_unique_path(os.path.join(target_root, target_name))
        entry = {
            "kind": media_kind,
            "source_root": source_root,
            "from": source_path,
            "to": target_path,
            "primary_tag": primary_tag,
        }
        if collection_name:
            entry["collection"] = collection_name
        try:
            _move_file(source_path, target_path, dry_run=dry_run)
        except Exception as exc:
            entry["error"] = str(exc)
            summary["totals"]["errors"] += 1
            summary["sources"][source_root]["errors"] += 1
            log_entries.append(entry)
            continue

        summary["totals"][media_kind] += 1
        summary["sources"][source_root][media_kind] += 1
        log_entries.append(entry)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Import 115 receive directories into tg root.")
    parser.add_argument(
        "--source",
        dest="sources",
        action="append",
        default=[],
        help="Source directory to import. Can be repeated.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview moves without changing files.")
    return parser


def main() -> None:
    args = _build_parser().parse_args()

    bot = MediaParserBot()
    tg_root = str(bot.settings.local_upload_root or "").strip()
    if not tg_root or not os.path.isdir(tg_root):
        raise SystemExit("tg root does not exist")

    source_dirs = [path for path in (args.sources or list(DEFAULT_SOURCE_DIRS)) if str(path or "").strip()]
    log_entries: List[Dict] = []
    summary: Dict = {
        "dry_run": bool(args.dry_run),
        "tg_root": tg_root,
        "sources": {},
        "totals": {"video": 0, "photo": 0, "file": 0, "skipped": 0, "errors": 0},
    }

    for source_root in source_dirs:
        source_root = os.path.abspath(source_root)
        source_summary = {"video": 0, "photo": 0, "file": 0, "skipped": 0, "errors": 0}
        summary["sources"][source_root] = source_summary
        if not os.path.isdir(source_root):
            source_summary["missing"] = True
            continue

        for current_root, dirs, files in os.walk(source_root):
            dirs[:] = [
                item
                for item in sorted(dirs, key=_archive_sort_key)
                if item not in SKIP_DIR_NAMES
                and not item.startswith(".")
                and not _is_temp_path(os.path.join(current_root, item))
            ]
            _process_directory(
                bot,
                source_root,
                current_root,
                files,
                log_entries,
                summary,
                dry_run=args.dry_run,
            )

        if not args.dry_run:
            _prune_empty_dirs(source_root)

    timestamp = time.strftime("%Y%m%d_%H%M%S", time.localtime())
    log_dir = os.path.join(BASE_DIR, "data")
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.abspath(os.path.join(log_dir, f"import_115_receive_to_tg_{timestamp}.json"))
    with open(log_path, "w", encoding="utf-8") as handle:
        json.dump({"summary": summary, "moves": log_entries}, handle, ensure_ascii=False, indent=2)

    print(json.dumps({"summary": summary, "log_path": log_path}, ensure_ascii=False))


if __name__ == "__main__":
    main()
