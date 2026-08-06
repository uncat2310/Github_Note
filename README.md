# 🗂️ GitHub_Note — 技术学习笔记

> 个人学习整理的技术笔记，涵盖 AI 编程工具、环境配置、部署运维、实用脚本等。

---

## 📖 文档列表

| # | 笔记 | 内容简介 |
|:-:|------|---------|
| 1 | [**nvm + Node.js + npm 安装指南**](nvm_npm_install_guide.md) | nvm 安装配置、Node.js 版本管理、npm 常用命令、常见问题排查 |
| 2 | [**Claude Code CLI 教程**](claude_code_guide.md) | 安装、认证方式（含 DeepSeek 第三方 API 包装脚本）、交互/打印模式、项目上下文配置 |
| 3 | [**Codex CLI 教程**](codex_cli_guide.md) | 安装、exec 模式、--full-auto / --yolo 参数、并行任务、注意事项 |
| 4 | [**Hermes Agent 教程**](hermes_agent_guide.md) | AI 代理框架安装、Telegram / 微信对接、网关管理、技能系统、多模型配置 |

---

## 📜 实用脚本

| 分类 | 脚本 | 说明 |
|:----:|------|------|
| 🗄️ **备份** | [`backup_replace.sh`](scripts/backup_replace.sh) | 项目源码滚动备份，保留最近 N 份时间戳备份 |
| | [`backup_to_115.sh`](scripts/backup_to_115.sh) | 异地备份到 115 网盘（CloudDrive 挂载） |
| | [`oneclick_restore_from_backup.sh`](scripts/oneclick_restore_from_backup.sh) | 从备份一键恢复 |
| | [`new_machine_install_restore.sh`](scripts/new_machine_install_restore.sh) | 新机器初始化安装与恢复 |
| 🧹 **清理** | [`system_hygiene_cleanup.sh`](scripts/system_hygiene_cleanup.sh) | 系统级清理（临时文件、日志、Docker 垃圾、Journal 日志） |
| | [`cleanup_yun_download.sh`](scripts/cleanup_yun_download.sh) | 网盘云下载目录清理 |
| 🌐 **代理节点** | [`hysteria2-alpine.sh`](scripts/hysteria2-alpine.sh) | Alpine Linux + OpenRC 的 Hysteria 2 安装、升级、状态、卸载脚本 |
| 🎬 **媒体处理** | [`move_av_to_video.sh`](scripts/move_av_to_video.sh) | AV 番号提取并归类到视频目录 |
| | [`reorg_video_categories.py`](scripts/reorg_video_categories.py) | 视频按规则分类整理 |
| | [`reclassify_tg_video_by_rules.py`](scripts/reclassify_tg_video_by_rules.py) | 历史视频文件按当前规则重分类 |
| | [`rules_config.py`](scripts/rules_config.py) | 分类规则配置文件 |
| | [`smart_purify_115_video.py`](scripts/smart_purify_115_video.py) | 115 网盘视频智能瘦身 |
| | [`import_115_receive_to_tg.py`](scripts/import_115_receive_to_tg.py) | 115 接收目录文件导入 Telegram |

---

## 🏷️ 分类索引

| 领域 | 相关笔记 |
|------|---------|
| 🚀 **环境配置** | nvm + Node.js 安装 |
| 🤖 **AI 编程工具** | Claude Code、Codex CLI |
| 🔌 **AI 代理框架** | Hermes Agent（对接 TG / 微信） |
| 🗄️ **备份恢复** | backup_replace / backup_to_115 / oneclick_restore |
| 🧹 **系统维护** | system_hygiene_cleanup / cleanup_yun_download |
| 🎬 **媒体管理** | move_av_to_video / reorg_video / reclassify / rules_config |

---

> 📝 持续更新中…

---

## 🌐 Alpine/OpenRC Hysteria 2 节点

[`scripts/hysteria2-alpine.sh`](scripts/hysteria2-alpine.sh) 面向 Alpine Linux 的 BusyBox `ash` 和 OpenRC 编写，适合当前这类没有 systemd 的轻量 VPS。脚本会安装官方 Hysteria 二进制、生成配置、创建 OpenRC 服务、加入 `default` 启动级别，并输出可导入 Sub-Store 的 `hysteria2://` 节点链接。

官方 Linux 安装脚本依赖 systemd，官方文档明确将 Alpine Linux 列为不支持的发行版；本脚本只补齐 Alpine/OpenRC 的服务管理层，Hysteria 二进制仍从官方发布下载地址获取。

### 快速安装

```sh
apk add --no-cache ca-certificates curl
wget -qO /tmp/hysteria2-alpine.sh \
  https://raw.githubusercontent.com/uncat2310/Github_Note/main/scripts/hysteria2-alpine.sh
chmod 700 /tmp/hysteria2-alpine.sh
HY2_PORT=443 sh /tmp/hysteria2-alpine.sh
```

默认配置使用：

- UDP `443` 监听；云厂商安全组也必须放行 UDP `443`；
- 自签名证书，客户端链接包含 `insecure=1`；
- `https://www.bing.com/` 作为 HTTP/3 masquerade 目标；
- `hysteria` OpenRC 服务账户；443 端口需要 `libcap` 的 `setcap`；
- 节点链接保存在 `/etc/hysteria/node-uri.txt`，客户端配置保存在 `/etc/hysteria/client.yaml`。

生产环境建议使用自己的域名和 ACME 证书：

```sh
HY2_DOMAIN=hy2.example.com \
HY2_EMAIL=admin@example.com \
HY2_PASSWORD='change-this-password' \
sh /tmp/hysteria2-alpine.sh
```

使用自签名证书时可通过 `HY2_SNI=bing.com` 指定客户端 SNI；如果域名、IP 或 masquerade 目标不是默认值，请显式设置 `HY2_HOST`、`HY2_SNI` 和 `HY2_MASQ_URL`。密码只允许字母、数字及 `. _ ~ -`，这样能安全地直接放进 URI。

### 常用操作

```sh
sh /tmp/hysteria2-alpine.sh --status
sh /tmp/hysteria2-alpine.sh --print-node
HY2_VERSION=v2.9.2 sh /tmp/hysteria2-alpine.sh  # 固定版本升级
sh /tmp/hysteria2-alpine.sh --remove
```

`--remove` 会删除 `/etc/hysteria` 下的配置、证书和已生成的节点链接；执行前请先备份需要保留的密钥。脚本升级时会把旧 `config.yaml` 备份为带时间戳的 `.bak.*` 文件。

更多配置说明请参阅 [Hysteria 2 官方安装文档](https://v2.hysteria.network/docs/getting-started/Installation/)、[服务端配置](https://v2.hysteria.network/docs/getting-started/Server/) 和 [URI 规范](https://v2.hysteria.network/docs/developers/URI-Scheme/)。节点 URI 含认证密码，不要把 `/etc/hysteria/node-uri.txt` 或实际链接提交到公开仓库。
