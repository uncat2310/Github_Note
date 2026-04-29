# nvm + Node.js + npm 安装教程

---

## 一、安装 nvm（Node Version Manager）

### 方式一：官方安装脚本（推荐）
```bash
# 使用 install.sh 一键安装
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
```

### 方式二：通过 wget 安装
```bash
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
```

### 方式三：从 Git 仓库手动安装
```bash
# 克隆 nvm 仓库到 ~/.nvm
git clone https://github.com/nvm-sh/nvm.git ~/.nvm

# 切换到最新稳定版
cd ~/.nvm
git checkout v0.40.3

# 在 .bashrc 中添加加载配置
source ~/.nvm/nvm.sh
```

---

## 二、配置 nvm

### 自动加载配置
安装脚本会自动修改 `~/.bashrc`，添加以下内容：
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # 加载 nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # 加载自动补全
```

### 立即生效
```bash
# 重新加载 .bashrc
source ~/.bashrc

# 或直接加载 nvm
source ~/.nvm/nvm.sh
```

### 验证安装
```bash
nvm --version
# 输出: 0.40.3
```

---

## 三、安装 Node.js 和 npm

### 查看可用的 Node.js 版本
```bash
# 列出所有远程可用版本
nvm ls-remote

# 只列出 LTS（稳定）版本
nvm ls-remote --lts
```

### 安装指定版本

```bash
# 安装最新的 LTS 版本（推荐）
nvm install --lts

# 安装最新版
nvm install node

# 安装指定版本
nvm install 18
nvm install 20
nvm install 22
nvm install 24.14.1
```

### 切换 Node.js 版本

```bash
# 使用指定版本
nvm use 22

# 使用 LTS 版本
nvm use --lts

# 使用最新版
nvm use node

# 查看当前使用的版本
nvm current
```

### 设置默认版本
```bash
nvm alias default 22       # 指定版本
nvm alias default --lts    # 最新的 LTS
nvm alias default node     # 最新版
```

### 查看已安装版本
```bash
nvm ls
# 输出示例：
#        v18.20.7
# ->     v22.15.1
#        v24.14.1
# default -> lts/* (-> v22.15.1)
```

---

## 四、验证 npm

安装 Node.js 时会自动附带 npm。

```bash
# 查看 npm 版本
npm --version

# 查看 Node.js 版本
node --version
```

---

## 五、npm 常用命令

### 包管理
```bash
# 安装包（本地）
npm install package-name

# 安装为开发依赖
npm install -D package-name

# 全局安装
npm install -g package-name

# 卸载包
npm uninstall package-name

# 更新包
npm update package-name

# 列出已安装包
npm list
npm list -g --depth=0   # 全局安装的包
```

### 项目初始化
```bash
npm init                        # 交互式创建 package.json
npm init -y                     # 快速创建（使用默认值）
```

---

## 六、常见问题

### 1. `nvm: command not found`
**原因**: nvm 没有加载到 shell 中

**解决**:
```bash
# 手动加载
source ~/.nvm/nvm.sh

# 或检查 .bashrc 是否有以下内容
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

### 2. `npm: command not found`
**原因**: Node.js 没有安装或没有切换到对应版本

**解决**:
```bash
# 安装 Node.js
nvm install --lts

# 或切换版本
nvm use --lts
```

### 3. 切换 Node 版本后，之前全局安装的 npm 包不见了
**原因**: 每个 Node 版本有独立的全局包目录

**解决**:
```bash
# 在新版本中重新安装
npm install -g package-name

# 或者安装时指定版本
nvm install 22 --reinstall-packages-from=20
```

### 4. 权限错误（EACCES: permission denied）
**原因**: 不要用 sudo npm install -g

**解决**:
```bash
# 方式一：使用 nvm（推荐，自动处理权限）
# nvm 安装的 Node.js 全局包目录在用户家目录下

# 方式二：配置 npm 前缀
npm config set prefix ~/.npm-global
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 七、安装全局常用工具

```bash
# 安装 Claude Code
npm install -g @anthropic-ai/claude-code

# 安装 Codex CLI
npm install -g @openai/codex

# 更新 npm 自身
npm install -g npm@latest

# 其他常用全局工具
npm install -g yarn          # 替代 npm 的包管理器
npm install -g pnpm          # 更快的包管理器
npm install -g typescript    # TypeScript 编译器
npm install -g ts-node       # TypeScript 直接运行
npm install -g nodemon       # 文件变更自动重启
npm install -g eslint        # 代码检查
npm install -g prettier      # 代码格式化
```

---

## 八、卸载

### 卸载指定 Node.js 版本
```bash
nvm uninstall 18
```

### 卸载 nvm
```bash
# 删除 nvm 目录
rm -rf ~/.nvm

# 从 .bashrc 中移除 nvm 相关行
# 编辑 ~/.bashrc，删除以下内容：
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```
