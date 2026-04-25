
---

# 🚀 VPS Hosting Full Deployment Guide

> **Author:** Arman Mia  
> **Last Updated:** 25 April 2026  
> **Stack:** Node.js, Express, Next.js, MongoDB, PM2, Nginx, SSL  

---

## 📑 Table of Contents

1. [Basic Setup (ZSH, Node, NVM, PNPM, PM2)](#1-basic-setup)
2. [GitHub CLI & Git Setup](#2-github-setup)
3. [Project Folder Setup & Clone](#3-project-setup)
4. [Nginx Deployment with SSL](#4-nginx-deployment)
5. [Project Deploy Commands](#5-deploy-commands)
6. [Frontend Deploy Guide](#6-frontend-deploy)
7. [MongoDB Local Setup](#7-mongodb-setup)
8. [Extra Commands](#8-extra-commands)
9. [Ecosystem Config Files](#9-ecosystem-files)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Basic Setup

**Script File:** `setup.sh` / `linux_setup_configuration.sh`

**Purpose:** Install ZSH Shell, Node.js (LTS), NVM, PNPM, Bun, PM2

### 📝 Step by Step

```bash
# Step 1: Create the setup file
vi setup.sh
# Press i to enter insert mode
# Ctrl + Shift + V to paste the script
# Press ESC → type :wq → Enter to save

# Step 2: Check file exists
ls

# Step 3: Make executable and run
chmod +x setup.sh
bash setup.sh
# Alternative: ./setup.sh

# Step 4: When asked "Do you want to change default shell to zsh?" → type: y
# Step 5: After completion, exit and reconnect
exit
ssh root@your_ip -p your_port
```

### 📄 Complete Script

<details>
<summary>Click to expand - setup.sh</summary>

```bash
#!/bin/bash

# Update and upgrade system
sudo apt update && sudo apt upgrade -y

# Install necessary packages
sudo apt install -y build-essential curl file git zsh

# Install zsh and set it as default shell
sudo chsh -s $(which zsh)

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Clone zsh-autosuggestions plugin
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Clone zsh-syntax-highlighting plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Add plugins to ~/.zshrc
plugins_to_add=(git zsh-autosuggestions zsh-syntax-highlighting nvm jsontools dirhistory history colored-man-pages)

# Ensure ~/.zshrc exists
touch ~/.zshrc

# Add plugins to ~/.zshrc if they are not already present
for plugin in "${plugins_to_add[@]}"; do
    if ! grep -q "^plugins=.*$plugin.*" ~/.zshrc; then
        sed -i "s/^plugins=(/plugins=($plugin /" ~/.zshrc
    fi
done

# Install NVM (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Configure NVM
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# Setup NodeJs
nvm install --lts

# PM2 && PNPM Installation
npm i -g pm2 bun pnpm

# Version Checking NodeJs
echo "Node Version"
node -v

# Print versions and information
echo "Zsh version:"
zsh --version

echo "Location of zsh:"
which zsh

echo "Details about zsh installation:"
whereis zsh

echo "Current default shell:"
echo $SHELL

# Source .zshrc to apply changes
source ~/.zshrc

# Done
echo "Setup completed."
```
</details>

---

## 2. GitHub Setup

**Script File:** `git.sh` / `git_user_setup.sh`

**Purpose:** Install GitHub CLI, authenticate GitHub account, configure Git credentials

### 📝 Step by Step

```bash
# Step 1: Create the git file
vi git.sh
# Press i → Paste script → ESC → :wq

# Step 2: Make executable and run
chmod +x git.sh
bash git.sh
```

### 🖥️ Setup Steps (Interactive)

| Question | Answer |
|:---|:---|
| What account do you want to log into? | `GitHub.com` |
| Preferred protocol for Git operations? | `HTTPS` |
| Authenticate Git with your GitHub credentials? | `Yes` |
| How would you like to authenticate? | `Login with a web browser` |

```bash
# One-time code will appear
# Visit: https://github.com/login/device
# Enter the one-time code
# Complete authentication
```

| Question | Answer |
|:---|:---|
| Your GitHub email: | `github@smtech24.com` |
| Your GitHub username: | `Your GitHub Username` |

### 📄 Complete Script

<details>
<summary>Click to expand - git.sh</summary>

```bash
#!/bin/bash

# Install wget if not present
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
&& sudo mkdir -p -m 755 /etc/apt/keyrings \
&& out=$(mktemp) && wget -nv -O "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
&& cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt update \
&& sudo apt install gh -y

# Configure GitHub CLI and Git credentials
git config --global credential.helper store
gh auth login

# Prompt user for email and name
read -p "Your GitHub email: " email
read -p "Your GitHub username: " name

# Set git global config
git config --global user.email "$email"
git config --global user.name "$name"
```
</details>

---

## 3. Project Setup

**Purpose:** Create project folder, clone repositories

### 📝 Step by Step

```bash
# Step 1: Create folder
mkdir /var/www
cd /var/www
pwd

# Step 2: Clone projects
# Frontend (example)
git clone https://github.com/your-username/your-frontend.git

# Backend (example)
git clone https://github.com/your-username/your-backend.git
# OR using gh CLI for private repos
gh repo clone your-username/your-backend

# Step 3: Navigate to project
cd project_name
ls

# Step 4: Clear screen
clear
```

---

## 4. Nginx Deployment

**Script File:** `deploy.sh` / `nginx deployment conf.d.sh`

**Purpose:** Configure Nginx reverse proxy with SSL certificate

### ⚠️ Important
- Must have a **real domain** pointed to your VPS IP
- Run from **root folder** (`/root`)

### 📝 Step by Step

```bash
# Step 1: Go to root folder
cd /root
pwd
# Output must be: /root

# Step 2: Create deploy file
vi deploy.sh
# Press i → Paste script → ESC → :wq

# Step 3: Make executable and run
chmod +x deploy.sh
bash deploy.sh
```

### 📝 Inputs Required

| Input | Example | Note |
|:---|:---|:---|
| Backend Port | `3001` or `5001` | Your app's running port |
| Domain Name | `api.yourdomain.com` | NO http/https prefix |
| Email | `your@email.com` | Official email recommended |

### 🔍 Verify Nginx Setup

```bash
# Check Nginx config
cd /etc/nginx/conf.d
ls
cat your-domain.conf

# Check project folder
cd /var/www
ls
cd project_name
ls
```

### 📄 Complete Script

<details>
<summary>Click to expand - deploy.sh</summary>

```bash
#!/bin/bash

# ======================
# NGINX + SSL Deployment Script
# ======================

set -euo pipefail

# --- Defaults & Flags ---
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) echo "Usage: $0 [-n|--dry-run] [-v|--verbose]"; exit 1 ;;
    esac
done

# --- Logging Setup ---
LOGFILE="/var/log/nginx-deploy.log"
exec > >(tee -a "$LOGFILE") 2>&1

if $VERBOSE; then
    set -x
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Ensure Running as Root ---
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root or via sudo."
    exit 1
fi

# --- Retryable apt update ---
apt_update() {
    for i in {1..5}; do
        if apt update; then
            return 0
        fi
        sleep 2
    done
    log_error "Failed to update package list after multiple attempts."
    exit 1
}

# --- Check & Install Package ---
install_pkg() {
    local pkg=$1
    if ! dpkg -l | grep -qw "$pkg"; then
        log_info "Installing $pkg..."
        if ! $DRY_RUN; then
            apt install -y "$pkg"
        fi
    else
        log_info "$pkg already installed."
    fi
}

# --- Validate Port Number ---
validate_port() {
    local p=$1
    if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
        return 1
    fi
    return 0
}

check_port_free() {
    local p=$1
    if lsof -i :"$p" | grep -q LISTEN; then
        return 1
    fi
    return 0
}

# --- Check Domain Resolvability (timeout 2s) ---
domain_resolves() {
    local d=$1
    if dig +time=2 +short "$d" | grep -q '\.'; then
        return 0
    fi
    return 1
}

# ===== Main =====
log_info "Starting deployment script..."
apt_update

# --- Install Required Packages ---
for pkg in nginx certbot python3-certbot-nginx ufw dnsutils; do
    install_pkg "$pkg"
done

# --- Verify certbot ---
if ! command -v certbot >/dev/null; then
    log_error "certbot not found after installation."
    exit 1
fi
log_info "certbot is installed: $(certbot --version || true)"

# --- UFW Setup ---
if ufw status | grep -q inactive; then
    log_info "Enabling UFW with restrictive defaults..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
else
    log_info "UFW already active. Ensuring required ports are open..."
fi

# Always allow SSH, HTTP, HTTPS
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp


# --- Prompt for Application Port ---
while true; do
    read -p "Enter the port number for your application: " APP_PORT
    if ! validate_port "$APP_PORT"; then
        log_error "Invalid port. Must be 1–65535."
        continue
    fi
    if ! check_port_free "$APP_PORT"; then
        log_error "Port $APP_PORT is in use."
        continue
    fi
    break
done

# --- Prompt for Domain & Email ---
read -p "Enter your domain (e.g. example.com): " DOMAIN
if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
    log_error "Invalid domain name."
    exit 1
fi
read -p "Enter your email for Let's Encrypt registration: " EMAIL

# --- Paths & Config ---
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

# --- Remove Old Config ---
if [ -f "$NGINX_CONF" ]; then
    log_info "Removing old Nginx config for $DOMAIN..."
    rm -f "$NGINX_CONF"
fi

# --- Write New Config ---
log_info "Creating Nginx config for $DOMAIN → port $APP_PORT"
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# --- Validate & Reload Nginx ---
log_info "Testing Nginx configuration..."
nginx -t
log_info "Reloading Nginx (graceful)..."
nginx -s reload

# --- Obtain / Renew SSL Certificate ---
if certbot certificates | grep -q "Domains:.*\b${DOMAIN}\b"; then
    log_info "Certificate for $DOMAIN already present — skipping issue."
else
    log_info "Issuing certificate for $DOMAIN..."
    if ! domain_resolves "www.$DOMAIN"; then
        log_info "www.$DOMAIN does not resolve. Issuing for $DOMAIN only."
        certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
    else
        certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
    fi
fi

# --- Setup Renewal Cron Job (if not present) ---
if ! crontab -l | grep -q 'certbot renew'; then
    log_info "Adding daily certbot renew cron job..."
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
fi

log_info "Deployment complete! Your site is live at https://$DOMAIN"
if $DRY_RUN; then
    log_info "*** Dry run mode — no changes were applied ***"
fi
```
</details>

---

## 5. Deploy Commands

### 🚀 Full Deploy (Backend with Prisma)

```bash
pnpm i && pnpm prisma generate && pnpm build && pm2 restart ecosystem.config.js && systemctl restart nginx
```

### 🚀 Deploy Without Prisma

```bash
pnpm i && pnpm build && pm2 restart ecosystem.config.js && systemctl restart nginx
```

### 🔄 PM2 Restart Only

```bash
pm2 restart ecosystem.config.js && systemctl restart nginx
```

### 📋 PM2 Logs

```bash
pm2 logs <number>
pm2 logs 0
pm2 logs starter_backend
```

### 🛠️ bcrypt Error Fix

```bash
npm rebuild bcrypt
pnpm i
```

### 🔓 Open New Port in Firewall

```bash
sudo ufw allow <port>/tcp
sudo ufw reload
# Example for backend port 5001
sudo ufw allow 5001/tcp
```

---

## 6. Frontend Deploy

### 📝 Step by Step

```bash
# Go to project folder
cd /var/www
ls
cd frontend_name

# No prisma needed in frontend
pnpm i
pnpm build
```

### ⚠️ If ecosystem file missing

```bash
vi ecosystem.config.js
# Paste config → Save (:wq)
pnpm i
```

### 🔒 SSL Fix for Domain

```bash
sudo certbot -d domain.com -d www.domain.com
```

### 🚀 Run deploy.sh for Frontend

```bash
cd /root
bash deploy.sh
# Provide: frontend port + domain + email
```

---

## 7. MongoDB Setup

**Script File:** `mongod.sh`

**Purpose:** Install MongoDB 8.0 locally with Replica Set

### ⚠️ Requirement
- Minimum **1GB RAM** (2GB recommended)
- At least **2GB free disk space**

### 📝 Step by Step

```bash
# Step 1: Go to root
cd

# Step 2: Create mongod file
vi mongod.sh
# Press i → Paste script → ESC → :wq

# Step 3: Make executable and run
chmod +x mongod.sh
bash mongod.sh
```

### 🔧 After MongoDB Install

```bash
# Update .env with new MongoDB URL
cd /var/www/your-backend
nano .env
# Change DATABASE_URL to:
DATABASE_URL="mongodb://localhost:27017/your-db-name?replicaSet=rs0"

# Restart PM2
pm2 restart your-backend-name
```

### 📄 Complete Script

<details>
<summary>Click to expand - mongod.sh</summary>

```bash
#!/bin/bash
set -euo pipefail

# 1) Non‑interactive APT
export DEBIAN_FRONTEND=noninteractive

# 2) Detect Ubuntu codename
CODENAME=$(grep -E '^UBUNTU_CODENAME=' /etc/os-release | cut -d= -f2)
echo "→ Detected Ubuntu: $CODENAME"

# 3) Install prerequisites + MongoDB without prompts
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    gnupg curl

# 4) Add MongoDB GPG key & repo
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
  | sudo gpg -o /usr/share/keyrings/mongodb-archive-keyring.gpg --dearmor

cat <<EOF | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
deb [signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg] \
    https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/8.0 multiverse
EOF

# 5) Install MongoDB packages
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    mongodb-org

# 6) Create data/log dirs
sudo mkdir -p /var/lib/mongodb /var/log/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb

# 7) Write your custom mongod.conf
sudo tee /etc/mongod.conf >/dev/null <<'EOL'
storage:
  dbPath: /var/lib/mongodb
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 0.0.0.0
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
replication:
  replSetName: rs0
EOL

# 8) Restart & enable
sudo systemctl daemon-reload
sudo systemctl enable --now mongod
sudo systemctl restart mongod

# 9) Give MongoDB a moment
sleep 5

# 10) Initialize replica set
echo "→ Initializing replica set…"
mongosh --quiet --eval '
  rs.initiate({
    _id: "rs0",
    members: [
      { _id: 0, host: "localhost:27017" }
    ]
  });
'

# 11) Show status & connection URL
echo "→ Replica set status:"
mongosh --quiet --eval 'printjson(rs.status())'

echo -e "\nMongoDB connection URL:"
echo "mongodb://localhost:27017/?replicaSet=rs0"
```
</details>

---

## 8. Extra Commands

### 📁 File Operations

```bash
# List files
ls

# Delete project folder
cd /var/www
sudo rm -rf project_name

# Clone fresh copy
git clone https://github.com/username/project.git
```

### 🔌 Port & Firewall

```bash
# Check UFW status
sudo ufw status

# Open a port
sudo ufw allow 13002
sudo ufw allow 5001/tcp

# Restart Nginx
sudo systemctl restart nginx
```

### 📦 Package Management

```bash
# Install specific packages
pnpm add uuid
pnpm add ws
pnpm add -D @types/ws

# Install PNPM globally (if missing)
npm install -g pnpm
```

### 🔑 SSH Key (for GitHub/VM Access)

```bash
# Generate SSH Key
sudo ssh-keygen -t ed25519 -C "vm-access"

# View public key
cd ~/.ssh
cat id_ed25519.pub
```

### 🧹 System Cleanup

```bash
# Clean disk space
sudo apt clean
sudo apt autoremove -y
rm -rf /var/cache/apt/archives/*
rm -rf /tmp/*

# Clear NPM cache
npm cache clean --force

# Clear PNPM cache
pnpm store prune
rm -rf ~/.pnpm-store

# Clear journal logs
sudo journalctl --vacuum-size=5M
```

### 🐚 ZSH Error Fix

```bash
# If zsh not found
source ~/.zshrc
```

---

## 9. Ecosystem Files

### Next.js / Frontend

```javascript
// for nextjs project

module.exports = {
  apps: [
    {
      name: "project-client",
      script: "node_modules/next/dist/bin/next",
      args: "start",
      env: {
        NODE_ENV: "production",
        PORT: 3001
      },
    },
  ],
};
```

### Express / Backend

```javascript
// for modular nodejs project

module.exports = {
    apps: [
        {
            name: 'project-server',
            script: './dist/server.js',
            args: 'start',
            env: {
                NODE_ENV: 'production',
            },
        },
    ],
};
```

---

## 10. Troubleshooting

| Problem | Solution |
|:---|:---|
| **bcrypt error** | `npm rebuild bcrypt` then `pnpm i` |
| **Port not accessible** | `sudo ufw allow <port>/tcp` |
| **Nginx not restarting** | `sudo systemctl restart nginx` |
| **PM2 app not starting** | `pm2 logs <app-name>` check errors |
| **Disk full** | `df -h` → `apt clean` → `rm -rf /tmp/*` |
| **Out of memory** | `export NODE_OPTIONS="--max-old-space-size=512"` |
| **PNPM killed** | Create swap: `sudo fallocate -l 1G /swapfile` |
| **ZSH not found** | `source ~/.zshrc` |
| **GitHub clone failed** | Use `gh repo clone user/repo` for private repos |
| **MongoDB connection failed** | `systemctl status mongod` check if running |

---

## 📊 Quick Reference - VPS Info

| Item | Value |
|:---|:---|
| **Provider** | TierHive (Free) |
| **OS** | Ubuntu 22.04 LTS |
| **RAM** | 1 GB (1024 MB) |
| **Disk** | 8 GB NVMe SSD |
| **Node.js** | v24.x LTS (via NVM) |
| **Package Manager** | PNPM + NPM |
| **Process Manager** | PM2 |
| **Web Server** | Nginx (optional) |
| **Database** | MongoDB 8.0 (local) |
| **Firewall** | UFW |

---

## 🎯 Workflow Summary

| Step | Script | Time |
|:---|:---|:---|
| 1. Basic Setup | `setup.sh` | 5-10 min |
| 2. GitHub Setup | `git.sh` | 2 min |
| 3. Clone Projects | Manual | 1 min |
| 4. Install Dependencies | `pnpm i` | 2-5 min |
| 5. Build & Start | `pm2 start` | 1 min |
| 6. Nginx Setup | `deploy.sh` | 3 min |
| 7. MongoDB Setup | `mongod.sh` | 3-5 min |
| **Total Time** | | **~20-30 min** |

---

> 💡 **Pro Tip:** Always check `ufw status` after deploying new services to ensure ports are open.

---

**© 2026 Arman Mia. All rights reserved.**

---
