#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
兼容入口：历史脚本 smart_purify_115_video.py

当前统一改用 reclassify_tg_video_by_rules.py 的规则。
本脚本仅作为视频重整的快捷别名：
- 默认 dry-run（只预览，不改动）
- 加 --execute 才实际执行
"""
import argparse
import os
import runpy
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)


def main() -> None:
    parser = argparse.ArgumentParser(description="重整 115 tg/video（默认 dry-run）")
    parser.add_argument("--execute", action="store_true", help="实际执行移动（默认只预览）")
    parser.add_argument("--root", default="", help="video 根目录（默认: <LOCAL_UPLOAD_ROOT>/video）")
    args = parser.parse_args()

    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reclassify_tg_video_by_rules.py")
    if not os.path.exists(script_path):
        raise SystemExit("missing script: reclassify_tg_video_by_rules.py")

    # 保持历史参数兼容：--execute 对应新脚本 --apply。
    argv = ["reclassify_tg_video_by_rules.py"]
    if args.execute:
        argv.append("--apply")
    else:
        argv.append("--dry-run")

    if args.root:
        argv.extend(["--root", os.path.abspath(args.root)])

    print("[compat] smart_purify_115_video.py -> reclassify_tg_video_by_rules.py")
    sys.argv = argv
    runpy.run_path(script_path, run_name="__main__")


if __name__ == "__main__":
    main()
