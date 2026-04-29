#!/usr/bin/env python3
"""
全量清理 云下载 目录：
1. 识别广告文件 → 删除
2. 视频文件（非广告）→ 移到 tg/video/
3. 图片文件（非广告）→ 移到 tg/photo/
4. 剩余无关文件（apk/html/txt等广告）→ 删除
5. 清理空目录
6. 最后自动执行 reclassify_tg_video_by_rules.py 分类
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YUNDOWNLOAD = "/home/CloudDrive/115open/云下载"
TG_VIDEO = "/home/CloudDrive/115open/tg/video"
TG_PHOTO = "/home/CloudDrive/115open/tg/photo"
RECLASSIFY_SCRIPT = os.path.join(BASE_DIR, "scripts", "reclassify_tg_video_by_rules.py")

DRY_RUN = "--apply" not in sys.argv

# 视频扩展名
VIDEO_EXTS = {".mp4", ".mkv", ".mov", ".avi", ".wmv", ".flv", ".ts", ".m2ts", ".webm", ".m4v"}
# 图片扩展名
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".heic", ".heif"}
# 始终为广告的扩展名
AD_EXTENSIONS = {".html", ".htm", ".apk", ".url", ".chm"}
# 可能为广告的扩展名（需要进一步判断）
SUSPICIOUS_EXTS = {".txt", ".rar", ".zip", ".7z", ".pp"}

# 广告文件名关键词黑名单（匹配则删除）
AD_KEYWORDS = [
    # 广告视频/直播平台
    "台湾uu美少女直播",
    "台 妹 子 線 上",
    "妹妹在精彩表演",
    "在线美女聊天",
    "线上美女聊天",
    "线上现场直播",
    "直播大秀平台推荐",
    "N房间的精彩直播",
    "激情隨時看",
    "tuu97.com", "tuu95.com", "tuu33.com", "tuu32.com", "tuu29.com",
    "美女荷官",
    "直播大秀",
    # 广告社区
    "社 區 最 新 情 報",
    "社区最新情报",
    "1024社区",
    "1024草榴社区",
    "草榴社区",
    "t66y.com",
    "含羞草",
    "Xvideos",
    "暗网天堂",
    "淫妻NTR",
    "淫母",
    "熟女圈",
    "萝幼社",
    "萝莉岛",
    "海角乱伦",
    "妻友社区",
    "PornHub",
    "Twitter中文版",
    "YouTube成人版",
    "好色",
    # 广告链接/地址
    "489155.com",
    "877gg.cc", "888gm.cc", "599gg.cc",
    "gm36.cc", "gm96.cc",
    "22HY.CC", "GM.GM85.CC",
    "最 新 位 址",
    "最新地址获取",
    "获取最新地址",
    "最新地址",
    "收藏不迷路",
    "双击直达",
    "网址发布器",
    "安卓二维码",
    "聚 合 全 網",
    "扫码",
    "二维码",
    "扫码添加客服",
    "扫码下载",
    # 广告应用
    "最新版.apk",
    "成人色游",
    "成人游戏",
    "成人手游",
    "H手游",
    "男人必备",
    # 广告内容推广
    "91短视频", "91重口",
    "吸精污漫",
    "女神檔案",
    "斗罗",
    "七龍珠",
    "宝可梦",
    "星空天使",
    "猎艳传奇",
    "私房猛药",
    "助勃增硬",
    "重口免费会员",
    "重口猎奇视频暗网",
    "稀缺重口破解流出",
    "稀缺呦呦资源",
    "封禁资源色片",
    "揭秘全球萝莉",
    "萝莉岛揭秘",
    "热门动漫&精选涩漫",
    "十万原创成人博主",
    "妹团外卖",
    "全球好片看×站",
    "动漫黄游",
    "一键脱衣",
    "AI换脸",
    "AI脱衣",
    "伦友聚集中心",
    "全网最火 性爱视频",
    "3亿资源随便看",
    "真实乱伦分享",
    "圈养全球",
    "揭露淫魔富豪",
    "这个逼很开门",
    "上万影片无限看",
    "成人版",
    "大家都在这里",
    "成人资源无所不有",
]

# 特定目录完全不处理（纯广告目录）
PURE_AD_DIRS = {
    "DYDX024",
    "GMDLYJH",
    # 数字目录中的纯广告子目录
}

# 计数
stats = {"video_moved": 0, "image_moved": 0, "ad_deleted": 0, "errors": 0}


def is_ad_filename(filename: str) -> bool:
    """通过文件名判断是否为广告"""
    name_lower = filename.lower()

    # 以广告域名开头
    if re.match(r'^(tuu\d+|www\d*\.)', name_lower):
        return True

    for kw in AD_KEYWORDS:
        if kw.lower() in name_lower:
            return True

    return False


def get_file_category(filepath: str) -> str:
    """
    返回文件类别: 'ad', 'video', 'image', 'other'
    """
    filename = os.path.basename(filepath)
    ext = os.path.splitext(filename)[1].lower()

    # 始终为广告的扩展名
    if ext in AD_EXTENSIONS:
        return "ad"

    # 没有扩展名或奇怪扩展名 -> 大概率广告
    if not ext or ext in SUSPICIOUS_EXTS:
        if is_ad_filename(filename):
            return "ad"
        # .txt 可能是字幕，检查文件名
        if ext == ".txt":
            # 字幕文件通常很小，但广告txt也是小文件
            # 如果文件名含 ad 关键词则删除
            if is_ad_filename(filename):
                return "ad"
            # 否则保守处理，跳过
            return "skip"
        return "ad"  # .rar, .zip, 无扩展名 基本是广告

    # 视频文件
    if ext in VIDEO_EXTS:
        # 检查文件名是否为广告
        if is_ad_filename(filename):
            return "ad"

        # 检查文件大小（小于20MB的视频大概率是广告或预告片）
        try:
            fsize = os.path.getsize(filepath)
            if fsize < 20 * 1024 * 1024:  # 20MB
                return "ad"
        except OSError:
            pass

        return "video"

    # 图片文件
    if ext in IMAGE_EXTS:
        # gif 通常是实拍内容，保留
        if ext == ".gif":
            return "image"

        if is_ad_filename(filename):
            return "ad"

        # 检查图片大小（小于50KB的图片大概率是广告图标/二维码）
        try:
            fsize = os.path.getsize(filepath)
            if fsize < 50 * 1024:  # 50KB
                return "ad"
        except OSError:
            pass

        return "image"

    # 其他（json, srt, ass 等字幕/配置文件）
    if ext in {".srt", ".ass", ".json", ".nfo", ".torrent"}:
        return "skip"

    return "ad"


def safe_move(src: str, dst_dir: str, prefix: str = "") -> str | None:
    """安全移动文件到目标目录，处理重名"""
    os.makedirs(dst_dir, exist_ok=True)
    filename = os.path.basename(src)
    if prefix:
        filename = f"{prefix}_{filename}"
    dst = os.path.join(dst_dir, filename)
    if os.path.exists(dst):
        base, ext = os.path.splitext(filename)
        n = 2
        while os.path.exists(os.path.join(dst_dir, f"{base}_{n}{ext}")):
            n += 1
        dst = os.path.join(dst_dir, f"{base}_{n}{ext}")
    if DRY_RUN:
        return dst
    try:
        shutil.move(src, dst)
        return dst
    except Exception as e:
        print(f"  ❌ 移动失败: {e}")
        stats["errors"] += 1
        return None


def process_directory(dirpath: str):
    """处理单个目录"""
    dirname = os.path.basename(dirpath)
    print(f"\n📁 {dirname}")

    # 先收集所有文件
    all_files = []
    for root, _dirs, files in os.walk(dirpath):
        for f in files:
            all_files.append(os.path.join(root, f))

    if not all_files:
        # 空目录
        if not DRY_RUN:
            try:
                os.rmdir(dirpath)
                print(f"  🗑 空目录已删除")
            except:
                pass
        else:
            print(f"  → 空目录(将删除)")
        return

    dir_videos = 0
    dir_images = 0
    dir_ads = 0

    for filepath in all_files:
        category = get_file_category(filepath)

        if category == "ad":
            dir_ads += 1
            if not DRY_RUN:
                try:
                    os.remove(filepath)
                except Exception as e:
                    print(f"  ⚠ 删除失败: {os.path.basename(filepath)}: {e}")

        elif category == "video":
            dst = safe_move(filepath, TG_VIDEO)
            if dst:
                dir_videos += 1
                if DRY_RUN:
                    print(f"  🎬 → video/: {os.path.basename(filepath)}")

        elif category == "image":
            dst = safe_move(filepath, TG_PHOTO)
            if dst:
                dir_images += 1
                if DRY_RUN:
                    print(f"  🖼 → photo/: {os.path.basename(filepath)}")

        # 'skip' 不做处理

    if dir_videos or dir_images or dir_ads:
        print(f"  结果: 视频={dir_videos}  图片={dir_images}  广告已删={dir_ads}")
    else:
        print(f"  无可处理文件")

    stats["video_moved"] += dir_videos
    stats["image_moved"] += dir_images
    stats["ad_deleted"] += dir_ads

    # 清理空目录
    if not DRY_RUN:
        try:
            for root, dirs, _ in os.walk(dirpath, topdown=False):
                for d in dirs:
                    dpath = os.path.join(root, d)
                    try:
                        if not os.listdir(dpath):
                            os.rmdir(dpath)
                    except:
                        pass
            if os.path.isdir(dirpath) and not os.listdir(dirpath):
                os.rmdir(dirpath)
        except:
            pass


def run_reclassify():
    """执行视频重分类"""
    script = RECLASSIFY_SCRIPT
    if not os.path.exists(script):
        print(f"\n⚠ 未找到 reclassify 脚本: {script}")
        return
    print(f"\n🔄 运行视频重分类脚本...")
    result = subprocess.run(
        [sys.executable, script, "--apply", "--root", TG_VIDEO],
        capture_output=True, text=True, cwd=BASE_DIR,
    )
    for line in result.stdout.splitlines():
        print(f"   {line}")
    if result.stderr:
        for line in result.stderr.splitlines():
            print(f"   ⚠ {line}")


def main():
    mode = "预演 (dry-run)" if DRY_RUN else "正式执行"
    print("=" * 60)
    print(f"云下载 全量清理脚本")
    print(f"模式: {mode}")
    print(f"源: {YUNDOWNLOAD}")
    print(f"视频目标: {TG_VIDEO}")
    print(f"图片目标: {TG_PHOTO}")
    print("=" * 60)

    if not os.path.isdir(YUNDOWNLOAD):
        print(f"❌ 目录不存在: {YUNDOWNLOAD}")
        return 1

    # 获取所有子目录并按名称排序
    entries = sorted([
        os.path.join(YUNDOWNLOAD, d)
        for d in os.listdir(YUNDOWNLOAD)
        if os.path.isdir(os.path.join(YUNDOWNLOAD, d))
    ])

    for entry in entries:
        dirname = os.path.basename(entry)
        # 跳过纯广告目录
        if dirname in PURE_AD_DIRS:
            print(f"\n📁 {dirname} (纯广告目录，整体删除)")
            if not DRY_RUN:
                try:
                    shutil.rmtree(entry)
                    stats["ad_deleted"] += 1
                    print(f"  🗑 已删除")
                except Exception as e:
                    print(f"  ❌ 删除失败: {e}")
            continue
        process_directory(entry)

    print("\n" + "=" * 60)
    print("统计:")
    print(f"  视频移至 tg/video/: {stats['video_moved']}")
    print(f"  图片移至 tg/photo/: {stats['image_moved']}")
    print(f"  广告/垃圾已删除: {stats['ad_deleted']}")
    print(f"  错误: {stats['errors']}")
    print("=" * 60)

    # 如果不是预演，跑 reclassify
    if not DRY_RUN and stats['video_moved'] > 0:
        run_reclassify()

    if DRY_RUN:
        print("\n⚠ 预演模式，未做任何修改。确认后执行:")
        print("  python3 scripts/cleanup_yun_download.sh --apply")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
