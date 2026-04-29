# Claude Code CLI 安装与使用教程

> **版本**: v2.1.121 | **安装路径**: `/root/.nvm/versions/node/v24.14.1/bin/claude`

---

## 一、安装

### 前置条件
- **Node.js** >= 18.x（建议通过 nvm 安装）
- **npm**（随 Node.js 一起安装）

### 安装步骤

```bash
# 全局安装
npm install -g @anthropic-ai/claude-code

# 验证安装
claude --version
# 输出: 2.1.121 (Claude Code)
```

### 更新
```bash
claude update
# 或
npm update -g @anthropic-ai/claude-code
```

---

## 二、认证方式

### 方式一：官方 Claude API（需 Anthropic 账号）
```bash
claude auth login
# 浏览器中完成 OAuth 认证
```

### 方式二：第三方 Anthropic 兼容 API（如 DeepSeek）
创建包装脚本 `/usr/local/bin/claude-ds`：

```bash
#!/usr/bin/env bash
set -euo pipefail

export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_API_KEY="你的API_KEY"

# 模型映射
export ANTHROPIC_MODEL="deepseek-v4-flash"       # 默认模型
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro"
export ANTHROPIC_CUSTOM_MODEL_OPTION="deepseek-v4-pro"

# 子代理模型
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"

# 上下文窗口
export ANTHROPIC_MAX_INPUT_TOKENS=1000000

exec claude --effort max "$@"
```

添加到 `.bashrc`：
```bash
alias claude='claude-ds'
```

---

## 三、使用方法

### 打印模式（一次性任务，推荐）
```bash
# 简单的查询
claude --print -p "解释一下 Python 的 async/await"

# 代码任务
claude --print -p "为 src/api.py 添加错误处理" --allowedTools "Read,Edit" --max-turns 10

# 代码审查
cd /path/to/repo && git diff main...feature | claude --print -p "审查这些变更"
```

### 交互模式（多轮对话）
```bash
# 启动交互式会话
claude

# 带初始提示启动
claude "帮我重构这个模块"

# 继续上一次会话
claude --continue
```

### 关键参数

| 参数 | 作用 |
|------|------|
| `-p, --print` | 打印模式，一次性任务 |
| `--model` | 模型选择：`haiku`（flash）/ `sonnet`（pro） |
| `--effort` | 推理强度：`low` / `medium` / `high` / `max` |
| `--max-turns` | 最大循环次数（防止跑飞） |
| `--max-budget-usd` | 费用上限 |
| `--allowedTools` | 限制可用工具（如 `Read,Edit,Bash`） |
| `--dangerously-skip-permissions` | 自动批准所有操作 |
| `--output-format json` | JSON 结构化输出 |

---

## 四、项目上下文配置

### CLAUDE.md（项目记忆文件）
在项目根目录创建 `CLAUDE.md`：
```markdown
# 项目: MyAPI

## 架构
- FastAPI + SQLAlchemy
- PostgreSQL 数据库
- pytest 测试

## 命令
- make test — 跑测试
- make lint — 代码检查

## 规范
- Python 使用 4 空格缩进
- Type hints 必须写
```

### 会话内快捷记忆
```bash
# 在交互模式下使用 # 前缀快速添加记忆
# 本项目的代码风格使用 2 空格缩进
```

---

## 五、使用场景示例

### 代码开发
```bash
# 实现新功能
claude --print -p "实现 JWT 认证模块" --allowedTools "Read,Write,Bash" --max-turns 15

# 修复 Bug
claude --print -p "修复用户登录时 500 错误" --allowedTools "Read,Edit" --max-turns 10

# 编写测试
claude --print -p "为 auth.py 编写单元测试" --max-turns 10
```

### 代码审查
```bash
cd /path/to/repo && git diff main...feature-branch | \
  claude --print -p "审查这个 PR 的变更，检查 bug 和安全问题" --max-turns 1
```

### 从标准输入处理
```bash
cat 错误日志.txt | claude --print -p "分析这些错误日志的原因"
```
