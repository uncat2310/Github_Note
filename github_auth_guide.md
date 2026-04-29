# GitHub Token / SSH Authentication Guide

## 1. Personal Access Token (PAT) — 传统方式

### 创建 Token
1. 访问 https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. 设置权限：勾选 `repo`（私有仓库）、`admin:public_key`（管理 SSH 密钥）
4. 复制生成的 token

### 使用方法
```bash
# 通过 HTTPS 使用 Token 克隆/推送
git clone https://username:TOKEN@github.com/username/repo.git

# 或者存为环境变量
export GH_TOKEN=ghp_xxxxxxxxxxxx
```

## 2. SSH Key 认证 — 推荐方式

### 生成密钥对
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
# 或者指定文件名
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

### 添加密钥到 SSH Agent
```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

### 将公钥添加到 GitHub
1. 复制公钥：`cat ~/.ssh/id_ed25519.pub`
2. 访问 https://github.com/settings/keys
3. Click "New SSH Key"，粘贴公钥

### 测试连接
```bash
ssh -T git@github.com
# 成功输出: Hi username! You've successfully authenticated...
```

### 配置 known_hosts
```bash
ssh-keyscan github.com >> ~/.ssh/known_hosts
```

## 3. GitHub CLI (gh)

### 安装
```bash
# Linux
(type -p wget >/dev/null || sudo apt install wget -y) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update && sudo apt install gh -y
```

### 登录
```bash
gh auth login
# 选择 SSH 方式登录
# 或者用 Token：
echo $GH_TOKEN | gh auth login --with-token
```

### 常用命令
```bash
gh repo create repo-name --public --source=. --remote=origin --push
gh repo view
gh pr create
gh pr checkout 42
gh issue list
gh run list
```

## 4. 常见问题

### Permission denied (publickey)
- 检查密钥是否已添加到 GitHub
- 检查 SSH Agent 是否运行：`ssh-add -l`
- 确认用的是正确的密钥：`ssh -vT git@github.com`

### Host key verification failed
```bash
ssh-keyscan github.com >> ~/.ssh/known_hosts
```

### HTTPS 转 SSH
```bash
git remote set-url origin git@github.com:username/repo.git
```
