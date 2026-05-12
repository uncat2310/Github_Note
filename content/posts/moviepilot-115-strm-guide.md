---
title: "MoviePilot + 115网盘 Strm 插件：搭建丝滑的云端媒体库"
description: "用 MoviePilot 配合 115 网盘的 Strm 方案，无需下载即可建立 Emby/Jellyfin 媒体库"
date: 2026-05-12
tags: ["MoviePilot", "115", "Strm", "Emby", "媒体服务器", "NAS"]
---

## 前言

传统的媒体服务器方案需要先把视频下载到本地，再刮削元数据、整理入库。对于动辄几十 GB 的 4K 原盘，本地存储压力很大。

**Strm 方案** 解决了这个问题——通过一个只有几百字节的 `.strm` 文本文件指向云端视频，Emby/Jellyfin 读取 strm 文件后重定向到云盘直接播放。视频本身不用下载到本地，即点即播。

本文将介绍如何使用 **MoviePilot V2** + **115 网盘** + **Strm 插件** 搭建这套体系。

---

## 一、MoviePilot 是什么

[MoviePilot](https://github.com/jxxghp/MoviePilot) 是一个基于 NAStool 衍生的媒体库自动化管理工具，主要功能：

- **订阅管理**：自动搜索下载资源
- **媒体库整理**：自动重命名、归类
- **刮削元数据**：自动获取海报、简介、演员信息
- **Strm 支持**：配合云盘插件生成 strm 文件，无需下载即可入库

> 如果你已经有 Emby/Jellyfin，MoviePilot 可以作为它们的中枢控制器。

---

## 二、部署 MoviePilot

### 2.1 Docker 部署（推荐）

```yaml
# docker-compose.yml
version: "3"
services:
  moviepilot:
    image: jxxghp/moviepilot-v2:latest
    container_name: moviepilot
    restart: always
    ports:
      - "3000:3000"    # Web UI
      - "3001:3001"    # API
    volumes:
      - /path/to/config:/config           # 配置文件目录
      - /path/to/media:/media              # 媒体文件目录（如 115 挂载点）
      - /path/to/strm:/config/strm         # strm 文件输出目录（可选）
      - /path/to/downloads:/downloads      # 下载目录
    environment:
      - NGINX_PORT=3000
      - PORT=3001
      - PUID=1000
      - PGID=1000
      - UMASK=022
    network_mode: bridge
```

### 2.2 基础配置

启动后访问 `http://你的IP:3000`，首次进入需要：

1. **设置管理员账号密码**
2. **配置媒体库目录**：即上面 volumes 中的 `/media` 路径
3. **配置下载器**：qBittorrent / Transmission 等
4. **配置索引器**：用于搜索资源的站点

---

## 三、115 网盘的挂载方式

MoviePilot 要访问 115 网盘的文件，需要通过 CloudDrive2 将 115 挂载到本地。

### 3.1 安装 CloudDrive2

```bash
# 下载最新版
wget https://github.com/clouddrive/clouddrive2/releases/latest/download/clouddrive2-linux-amd64.deb
dpkg -i clouddrive2-linux-amd64.deb

# 启动服务
systemctl start clouddrive2
systemctl enable clouddrive2
```

访问 `http://你的IP:19798` 进行配置：

1. 用 115 账号扫码登录
2. 挂载到本地目录，如 `/mnt/115`
3. 设置开机自动挂载

> 注意：CloudDrive2 的 FUSE 挂载在大量小文件操作时较慢，但流媒体播放性能足够。

---

## 四、115 Strm 插件详解

### 4.1 什么是 Strm 文件

`.strm` 是一个纯文本文件，内容就是一行 **视频文件的 URL**：

```
https://你的MoviePilot地址/api/v1/plugin/StrmPlugin/redirect_url?pickcode=xxxxx
```

当 Emby/Jellyfin 扫描到这个文件时，会读取 URL 并播放。这个 URL 经过 MoviePilot 插件处理后，最终重定向到 115 的 CDN 视频流。

**优势：**

| 方案 | 本地占用 | 刮削速度 | 播放速度 |
|:----|:--------|:--------|:--------|
| 传统下载 | 几十 GB/部 | 快（本地文件） | 快（本地播放） |
| Strm 方案 | 几百字节/部 | 快（只需扫描文本文件） | 取决于宽带（直连 115 CDN） |

### 4.2 安装 Strm 插件

在 MoviePilot 中打开 **插件市场**（管理 → 插件市场）：

1. 搜索 **云盘Strm助手**（CloudStrmCompanion，作者 thsrite）
2. 点击安装
3. 也可以在设置中安装 **Strm重定向** 插件

### 4.3 配置云盘Strm助手

插件配置界面：

```
# 基础设置
电影strm路径: /config/strm/电影#/mnt/115/Emby/电影
电视剧strm路径: /config/strm/剧集#/mnt/115/Emby/剧集
AV strm路径: /config/strm/AV#/mnt/115/Emby/AV

# 格式说明
# 等号左边: 本地 strm 文件输出目录（相对于 /config）
# 等号右边: 115 云盘上的视频文件路径
```

**路径映射原理：**

```
/config/strm/AV#/mnt/115/Emby/AV
     ↑                    ↑
  本地strm目录       115云盘视频目录
```

插件会扫描 115 云盘 `/mnt/115/Emby/AV/` 下的视频文件，在本地 `/config/strm/AV/` 创建同名的 `.strm` 文件。

### 4.4 配置 Strm 重定向

安装 **Strm重定向** 插件后，配置好你的 MoviePilot 地址，strm 文件的内容就会指向你的 MoviePilot API 地址，播放时自动跳转到 115 CDN。

### 4.5 定时同步

插件支持两种同步模式：

| 模式 | 说明 | 推荐频率 |
|:----|:----|:--------|
| 增量同步 | 只扫描新文件，速度很快 | 每 1-2 小时 |
| 全量同步 | 重新扫描全部目录 | 每天凌晨 3:00 |

建议两个都启用——增量保证及时性，全量保证完整性。

---

## 五、Emby/Jellyfin 配置

### 5.1 添加媒体库

在 Emby 中添加库时：

```
库类型: 电影 / 电视剧
路径: /path/to/strm/AV   （对应你配置的 strm 输出目录）
元数据读取器: NFO（不联网刮削，纯读取本地 NFO）
```

### 5.2 NFO 纯读取模式

由于 strm 方案中元数据需要**已经提前准备好**（通过 TinyMediaManager 或 JavSP 等工具刮削），Emby 应设置为 **不联网获取元数据**：

1. 库设置中关闭所有在线元数据抓取器
2. 元数据保存器只保留 `Emby Xml`
3. 海报图片优先使用本地文件

---

## 六、自动化工作流（进阶）

完整的自动化流水线：

```
115离线下载 → 文件到云盘
    ↓
P115StrmHelper 增量扫描 → 生成本地 .strm 文件
    ↓
JavSP / TMM 刮削 strm → 写入 NFO + 海报
    ↓
Emby 扫描 strm 目录 → 读取 NFO → 更新媒体库
```

可以用 crontab 调度：

```bash
# 每 2 小时刮削新增 strm
15 */2 * * * cd /path/to && bash scrape_strm.sh --apply >> /var/log/scrape.log 2>&1

# 每天凌晨触发 Emby 全库刷新
0 4 * * * curl -X POST "http://127.0.0.1:8096/emby/Library/Refresh?api_key=你的KEY"
```

---

## 七、注意事项

### ⚠️ 已知问题

1. **FUSE 性能**：CloudDrive2 的 FUSE 挂载在大量小文件操作时较慢，建议 strm 文件保存在本地而非 FUSE 上
2. **非标番号**：部分资源（如 1pondo、Heyzo、加勒比）不符合标准番号格式，刮削器无法识别，建议手动处理或直接跳过
3. **Emby API 不可靠**：Emby 的 VirtualFolders API（增删媒体库）返回 204 但实际不生效，请使用 Web UI 操作
4. **多盘迁移**：strm 文件只包含 115 pickcode（文件永久 ID），迁移服务器只需替换域名即可

### 💡 最佳实践

- 所有 strm 文件保存在**本地磁盘**（不要放 FUSE 挂载点）
- 刮削目标为 strm 文件本身（而非原视频），速度极快
- 使用 NFO-only 模式（不联网刮削），保证元数据可控
- 定期备份 `/path/to/strm/` 目录（占用极小）

---

## 八、总结

这套方案的核心优势：

- ✅ **零本地存储**：视频文件全在 115 云盘，不占服务器空间
- ✅ **极快入库**：strm 文件 + NFO 纯文本，秒级扫描
- ✅ **即点即播**：Emby 通过 strm 重定向到 115 CDN，宽带够就能流畅播放
- ✅ **可迁移性强**：strm 文件几百字节，备份迁移毫无压力

适合场景：服务器硬盘小（如 512GB SSD VPS）、但有高速宽带的用户。用云盘做存储层，本地只跑服务，是最经济的媒体服务器方案。

---

*本文使用通用路径，所有 `/path/to/` 请替换为你的实际目录。*
