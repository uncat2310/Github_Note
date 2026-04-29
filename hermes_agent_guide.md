# Hermes Agent 安装与使用教程

Hermes Agent 是一款功能强大的 AI 代理框架，支持对接 Telegram、微信（WeChat）等多个平台。

---

## 一、安装

### 方式一：一键安装脚本（推荐）
```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

### 方式二：从源码安装
```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
pip install -e .
```

### 安装后验证
```bash
hermes --version
```

---

## 二、基础配置

### 配置文件位置
`~/.hermes/config.yaml`

### 核心配置结构

```yaml
# 模型配置
model:
  default: deepseek-v4-flash        # 默认模型
  provider: deepseek                 # 模型提供商

# 模型提供商配置
providers:
  deepseek:
    api_key: "你的DeepSeek API Key"   # 在 .env 中设置 DEEPSEEK_API_KEY
    base_url: https://api.deepseek.com

# 代理配置
agent:
  max_turns: 60                      # 每轮最大工具调用次数
  reasoning_effort: xhigh            # 推理强度

# 终端配置
terminal:
  backend: local                     # 使用本地终端

# TTS 语音合成
tts:
  provider: xiaomi                   # 语音引擎
  xiaomi:
    model: mimo-v2.5-tts             # TTS 模型
```

### 环境变量（.env 文件）
在 `~/.hermes/.env` 中配置 API 密钥：
```
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxx
XIAOMI_API_KEY=your_xiaomi_api_key
TELEGRAM_BOT_TOKEN=123456789:ABCdef...
```

---

## 三、对接 Telegram Bot

### 1. 创建 Telegram Bot
1. 在 Telegram 中搜索 **@BotFather**
2. 发送 `/newbot` 按提示创建
3. 保存得到的 Bot Token（格式：`123456789:ABCdef...`）

### 2. 配置 Telegram

在 `~/.hermes/config.yaml` 中添加：
```yaml
telegram:
  reactions: false                    # 是否回复表情反应
  channel_prompts: {}                 # 频道自定义提示词
```

在 `~/.hermes/.env` 中添加：
```
TELEGRAM_BOT_TOKEN=你的Bot Token
```

### 3. 启动 Telegram 网关
```bash
# 启动 Hermes
hermes start

# 首次启动时会自动扫描并显示可用的聊天/频道
# 选择你想要连接的对话
```

### 4. 配置平台工具集
```yaml
platform_toolsets:
  telegram:
    - hermes-telegram                 # Telegram 专用工具
```

---

## 四、对接微信（WeChat）

### 1. 实现方式
Hermes Agent 通过 **WeChatFerry** 协议接入微信，无需微信官方 API。

### 2. 配置微信

`~/.hermes/config.yaml` 中已自动生成：
```yaml
WEIXIN_DM_POLICY: allowlist          # 私信策略：白名单模式
WEIXIN_ALLOWED_USERS: "用户ID@im.wechat"  # 允许对话的用户
WEIXIN_ALLOW_ALL_USERS: false         # 不开放给所有用户
```

### 3. 微信登录
```bash
# 启动后会自动显示微信二维码
hermes start

# 用手机微信扫码登录
# 登录成功后 show 微信网关状态为 connected
```

### 4. 微信用户权限
- **白名单模式**：只有 `WEIXIN_ALLOWED_USERS` 中的用户可以私聊 Hermes
- **群聊**：需要将 Hermes 拉入群聊，并在群中 @ 机器人
- **发送文件**：终端可以操作本地文件系统

---

## 五、多平台网关管理

### 查看网关状态
```bash
hermes gateway status
# 输出示例：
# telegram: connected ✓
# weixin:   connected ✓
```

### 常用命令

| 命令 | 作用 |
|------|------|
| `hermes start` | 启动 Hermes（含网关） |
| `hermes stop` | 停止 Hermes |
| `hermes gateway status` | 查看各平台连接状态 |
| `hermes config set` | 修改配置 |
| `hermes setup` | 重新运行安装向导 |

---

## 六、技能系统

Hermes 内置了大量技能（Skills），覆盖开发、运维、创意等多个领域。

### 加载技能
```yaml
skills:
  external_dirs: []                  # 额外技能目录
```

### 内置技能分类
| 分类 | 包含技能 |
|------|---------|
| 🛠️ 开发工具 | `claude-code`, `codex`, `opencode` |
| 🎨 创意工具 | `ascii-art`, `pixel-art`, `excalidraw`, `p5js` |
| 📊 数据科学 | `jupyter-live-kernel` |
| 🐳 DevOps | `webhook-subscriptions` |
| 📝 笔记 | `obsidian` |
| 🤖 社交 | `xurl`（X/Twitter）, `yuanbao` |

### 使用技能
```bash
# 在聊天中直接描述需求，Hermes 会自动加载匹配的技能
# "帮我画一张系统架构图" → 加载 excalidraw 技能
# "帮我写一个 Python 贪吃蛇" → 加载 claude-code 技能
```

---

## 七、模型配置

### 支持的模型提供商

| 提供商 | 环境变量 | 示例模型 |
|--------|---------|---------|
| DeepSeek | `DEEPSEEK_API_KEY` | deepseek-v4-flash, deepseek-v4-pro |
| OpenAI | `OPENAI_API_KEY` | gpt-4o, gpt-4o-mini |
| Anthropic | `ANTHROPIC_API_KEY` | claude-sonnet-4, claude-opus-4 |
| Xiaomi | `XIAOMI_API_KEY` | mimo-v2.5（视觉/语音） |

### 多模型配置示例
```yaml
model:
  default: deepseek-v4-flash
  provider: deepseek

# 辅助功能使用不同模型
auxiliary:
  vision:
    provider: xiaomi                  # 视觉模型
    model: mimo-v2.5
  compression:
    provider: deepseek                # 上下文压缩
    model: deepseek-v4-flash
  tts:
    provider: xiaomi                  # 语音合成
    model: mimo-v2.5-tts
```

---

## 八、数据备份与迁移

### 备份全部数据
```bash
# Hermes Agent 完整数据在 ~/.hermes/ 目录
tar -czf hermes_backup.tar.gz ~/.hermes/
```

### 迁移到新机器
1. 新机器安装 Hermes Agent
2. 停止 Hermes Agent
3. 解压备份到 `~/.hermes/`
4. 恢复 `.env` 中的 API 密钥
5. 重新启动
6. Telegram Bot 直接可用
7. 微信需重新扫码登录
