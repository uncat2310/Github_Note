# New Machine Setup Guide

## 1. 基础环境配置

### 安装常用工具
```bash
apt update && apt install -y curl wget git vim tmux htop
```

### 配置 SSH
```bash
# 从旧机器复制 authorized_keys
scp old-machine:/root/.ssh/authorized_keys /root/.ssh/

# 或手动添加公钥
echo "ssh-ed25519 AAAA..." >> /root/.ssh/authorized_keys
```

## 2. 代码仓库同步

### 克隆已有仓库
```bash
# 先配好 SSH 密钥（见 github_auth_guide.md）
git clone git@github.com:username/tg-media-parser-bot.git
git clone git@github.com:username/local-image-gallery.git
```

### 一键恢复（如果有备份脚本）
```bash
cd /path/to/project
bash scripts/oneclick_restore_from_backup.sh
```

## 3. 环境变量配置

复制 `.env.example` 为 `.env` 并填入实际值：
```bash
cp .env.example .env
# 编辑 .env 填入 API 密钥、Token 等
```

## 4. Python 环境

### 使用系统 Python
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 使用自定义 Python 版本
```bash
# 示例：编译 Python 3.14.3
apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

cd /opt
wget https://www.python.org/ftp/python/3.14.3/Python-3.14.3.tar.xz
tar xf Python-3.14.3.tar.xz
cd Python-3.14.3
./configure --prefix=/opt/python-3.14.3 --enable-optimizations
make -j$(nproc)
make install
```

## 5. 服务部署

### systemd 服务配置
```bash
# 复制服务文件
cp *.service /etc/systemd/system/
cp *.timer /etc/systemd/system/

# 启用并启动
systemctl daemon-reload
systemctl enable --now tg-media-parser-bot.service
systemctl enable --now tg-media-parser-b-watch.service
systemctl enable --now tg-media-parser-dy-watch.service
```

### Caddy 反向代理
```bash
# 安装 Caddy
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/debian/debian any-version main" | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy

# 编辑 /etc/caddy/Caddyfile
# 示例见 local-image-gallery 的 README
systemctl reload caddy
```

## 6. 定时任务

```bash
# 编辑 crontab
crontab -e

# 常见任务示例：
# 每天凌晨清理临时文件
0 3 * * * /root/tg_media_parser_bot/scripts/system_hygiene_cleanup.sh

# 每小时备份
0 * * * * /root/tg_media_parser_bot/scripts/backup_to_115.sh
```

## 7. 云存储挂载 (CloudDrive2)

```bash
# 安装 CloudDrive2
# 访问 Web UI 登录，挂载 115 网盘和百度网盘

# 默认挂载点
# /home/CloudDrive/115open/
# /home/CloudDrive/百度网盘/
```
