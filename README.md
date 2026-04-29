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
