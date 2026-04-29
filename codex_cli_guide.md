# Codex CLI 安装与使用教程

> **版本**: 0.124.0 | **安装路径**: `/root/.nvm/versions/node/v24.14.1/bin/codex`

---

## 一、安装

### 前置条件
- **Node.js** >= 18.x
- **npm**（随 Node.js 一起安装）
- **Git** 仓库（Codex 必须在 Git 仓库内运行）

### 安装步骤

```bash
# 全局安装
npm install -g @openai/codex

# 验证安装
codex --version
# 输出: codex-cli 0.124.0
```

### 配置 API Key
```bash
# 方式一：环境变量
export OPENAI_API_KEY="你的API_KEY"

# 方式二：写入 .bashrc 永久生效
echo 'export OPENAI_API_KEY="你的API_KEY"' >> ~/.bashrc
```

---

## 二、使用方法

### 一次性执行（exec 模式）
```bash
# 必须在 Git 仓库内运行
cd /path/to/project

# 简单任务
codex exec "添加暗色模式切换功能"

# 全自动模式（自动批准文件更改）
codex exec --full-auto "重构 auth 模块，添加 JWT 支持"
```

### 无沙箱模式（最快）
```bash
# --yolo = 无沙箱、无确认，直接执行
codex exec --yolo "修复所有 lint 错误"
```

### 背景模式（长时间任务）
```bash
# 后端运行
codex exec --full-auto "实现完整的用户管理系统" &

# 查看输出
jobs
fg
```

---

## 三、关键参数

| 参数 | 作用 |
|------|------|
| `exec "prompt"` | 一次性执行（推荐） |
| `--full-auto` | 沙箱内自动批准文件更改 |
| `--yolo` | 无沙箱、无确认（最快但最危险） |

---

## 四、最佳实践

### 1. 简单任务（适合 Codex）
```bash
codex exec "写一个 Python 函数，将 Markdown 转换为 HTML"
```

### 2. 新建项目（需要临时 Git 仓库）
```bash
cd $(mktemp -d)
git init
codex exec "创建一个贪吃蛇游戏的 Python 实现"
```

### 3. 修改现有代码
```bash
cd /path/to/project
codex exec "优化 database.py 中的 SQL 查询，添加索引"
```

### 4. 批量任务（并行运行多个 Codex）
```bash
# 创建多个工作树
git worktree add -b fix/issue-1 /tmp/issue-1 main
git worktree add -b fix/issue-2 /tmp/issue-2 main

# 并行执行
cd /tmp/issue-1 && codex exec "修复 issue #1: 登录页面样式错乱" &
cd /tmp/issue-2 && codex exec "修复 issue #2: API 返回状态码错误" &

# 等待完成
wait
```

---

## 五、注意事项

### 必须记住
1. **必须在 Git 仓库内运行** — Codex 拒绝在非 Git 目录下执行
2. **`exec` 用于一次性任务** — 完成后自动退出
3. **`--yolo` 要小心** — 直接修改文件系统，适合信任的自动化场景
4. **Python 项目使用 `--full-auto`** — 在沙箱内自动批准

### 对比 Codex vs Claude Code

| 特性 | Codex CLI | Claude Code |
|------|-----------|-------------|
| 模型 | OpenAI o 系列 | Claude 系列 / 第三方 API |
| 依赖 | npm | npm |
| Git 要求 | 必须 | 建议 |
| 第三方 API | 不支持 | 支持（DeepSeek 等） |
| 打印模式 | `exec` | `--print` / `-p` |
| 优势 | 速度快、轻量 | 功能丰富、上下文管理 |
