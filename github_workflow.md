# GitHub Workflow 笔记

## 仓库管理

### 创建新仓库并推送
```bash
# 方式一：本地初始化后推送到已存在的空仓库
git init
git add -A
git commit -m "Initial commit"
git branch -m main
git remote add origin git@github.com:username/repo-name.git
git push -u origin main

# 方式二：使用 gh 直接创建
gh repo create repo-name --public --source=. --remote=origin --push
```

### 修改远程仓库地址
```bash
git remote set-url origin git@github.com:username/new-repo-name.git
```

### 查看远程仓库
```bash
git remote -v
```

## 分支管理

### 创建并切换分支
```bash
git checkout -b feature/new-feature
# 等同于
git branch feature/new-feature
git checkout feature/new-feature
```

### 推送新分支到远程
```bash
git push -u origin feature/new-feature
```

### 删除分支
```bash
# 本地
git branch -d feature/new-feature

# 远程
git push origin --delete feature/new-feature
```

### 合并分支
```bash
git checkout main
git merge feature/new-feature
```

## 提交管理

### 修改最近一次提交信息
```bash
git commit --amend -m "New commit message"
```

### 撤销提交（保留更改）
```bash
git reset --soft HEAD~1
```

### 撤销提交（丢弃更改）
```bash
git reset --hard HEAD~1
```

### 暂存当前更改
```bash
git stash
git stash pop  # 恢复
git stash list
```

## 忽略文件 (.gitignore)

常用规则：
```
# 环境变量
.env
.env.*

# Python
__pycache__/
*.pyc
venv/
.venv/

# 系统文件
.DS_Store
Thumbs.db

# IDE
.idea/
.vscode/
*.swp

# 数据库
*.db
*.sqlite

# 日志
*.log

# 二进制文件
bin/
*.exe
```

## Pull Request 流程

```bash
# 1. 从 main 创建功能分支
git checkout -b fix/issue-42

# 2. 开发和提交
git add .
git commit -m "fix: resolve issue #42"

# 3. 推送分支
git push -u origin fix/issue-42

# 4. 创建 PR（或通过 GitHub Web UI）
gh pr create --title "fix: resolve issue #42" --body "Description"

# 5. 合并 PR（在 GitHub 上操作或命令行）
gh pr merge 42
```

## 标签管理
```bash
# 创建标签
git tag v1.0.0

# 推送标签到远程
git push origin v1.0.0
```
