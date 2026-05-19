# 🚀 Production Deployment Guide

> **Stack:** Node.js · Express · Next.js · MongoDB · PM2 · Nginx · SSL  
> **Targets:** VPS (Ubuntu 22.04 LTS) · AWS EC2  
> **Author:** Arman Mia · **Last Updated:** May 2026  
> **Security Level:** Production-Grade

---

## 📑 Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Pre-Deployment Checklist](#2-pre-deployment-checklist)
3. [Server Hardening & Initial Setup](#3-server-hardening--initial-setup)
4. [Runtime Environment (Node, NVM, PNPM, PM2)](#4-runtime-environment)
5. [GitHub & Git Authentication](#5-github--git-authentication)
6. [Environment Variables & Secrets Management](#6-environment-variables--secrets-management)
7. [Project Setup & Deployment](#7-project-setup--deployment)
8. [MongoDB Setup (Local with Replica Set)](#8-mongodb-setup)
9. [Nginx Reverse Proxy & SSL](#9-nginx-reverse-proxy--ssl)
10. [PM2 Process Management](#10-pm2-process-management)
11. [CI/CD Pipeline (GitHub Actions)](#11-cicd-pipeline)
12. [Monitoring & Alerting](#12-monitoring--alerting)
13. [Logging Strategy](#13-logging-strategy)
14. [Backup & Recovery](#14-backup--recovery)
15. [AWS EC2 Specific Guide](#15-aws-ec2-specific-guide)
16. [Troubleshooting Reference](#16-troubleshooting-reference)
17. [Quick Reference Commands](#17-quick-reference-commands)

---

## 1. Architecture Overview

```
Internet
    │
    ▼
[Cloudflare DNS / Route 53]
    │
    ▼ :443 (HTTPS)
[Nginx — Reverse Proxy + SSL Termination]
    │               │
    ▼               ▼
[Next.js :3000]  [Express API :5001]
                    │
                    ▼
             [MongoDB :27017]
             (localhost only)

Process Manager: PM2 (cluster mode)
Firewall: UFW (VPS) / Security Groups (AWS)
Secrets: .env (chmod 600) / AWS SSM Parameter Store
Backups: mongodump → S3 / Backblaze B2 (daily cron)
Monitoring: UptimeRobot + PM2 Monit + Nginx logs
```

> **Rule:** MongoDB and backend ports are NEVER exposed to the internet.
> Only ports 22, 80, and 443 are publicly accessible.

---

## 2. Pre-Deployment Checklist

Complete every item before starting deployment.

### Server
- [ ] Ubuntu 22.04 LTS (minimum)
- [ ] At least 1 GB RAM (2 GB recommended for MongoDB builds)
- [ ] At least 10 GB disk space
- [ ] Root or sudo access via SSH key (no password auth)
- [ ] Domain name with DNS A record pointing to server IP (for SSL)

### Local Machine
- [ ] SSH key pair generated
- [ ] Public key added to server's `~/.ssh/authorized_keys`
- [ ] Domain DNS records propagated (`dig your-domain.com` returns server IP)

### Application
- [ ] `.env.production` prepared (never committed to Git)
- [ ] `ecosystem.config.js` ready in repo
- [ ] `pnpm-lock.yaml` committed and up-to-date
- [ ] Build tested locally (`pnpm build` succeeds)
- [ ] `/health` endpoint present in backend

---

## 3. Server Hardening & Initial Setup

Connect as root for this section only. All subsequent operations use the `deploy` user.

```bash
ssh root@YOUR_SERVER_IP
```

### 3.1 Create a Non-Root Deploy User

```bash
# Create deploy user
adduser deploy
usermod -aG sudo deploy

# Copy root SSH key to deploy user
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

### 3.2 SSH Hardening

```bash
# Edit SSH config
nano /etc/ssh/sshd_config
```

Set or verify these values:

```ini
Port 2222                    # Change from default 22 (adjust firewall after)
PermitRootLogin no           # Disable root login
PasswordAuthentication no    # Key-only authentication
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
AllowUsers deploy            # Whitelist only deploy user
X11Forwarding no
```

```bash
# Apply changes
systemctl restart sshd
```

> ⚠️ Open your new SSH port in the firewall BEFORE closing your current session.

### 3.3 Firewall Setup (UFW)

```bash
# Reset and configure UFW
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow only required ports
ufw allow 2222/tcp    # SSH (use your custom port)
ufw allow 80/tcp      # HTTP (for Let's Encrypt + redirect)
ufw allow 443/tcp     # HTTPS

# Enable firewall
ufw --force enable
ufw status verbose
```

> ❌ Do NOT open backend ports (3000, 5001, 27017) — Nginx proxies internally.

### 3.4 System Updates & Automatic Security Patches

```bash
apt update && apt upgrade -y

# Enable automatic security updates
apt install -y unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades
```

### 3.5 Swap Space (Critical for Low-RAM Servers)

Create swap before any build or install step:

```bash
# 2 GB swap (adjust for RAM: use 2x RAM up to 8 GB)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make permanent across reboots
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Tune swappiness for server workloads
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl -p

# Verify
free -h
swapon --show
```

### 3.6 Install Essential Utilities

```bash
apt install -y \
  build-essential curl git wget \
  zsh htop lsof dnsutils ufw \
  fail2ban logrotate certbot python3-certbot-nginx
```

### 3.7 Fail2Ban (Brute Force Protection)

```bash
# Copy default config
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
nano /etc/fail2ban/jail.local
```

Edit these values under `[DEFAULT]` and `[sshd]`:

```ini
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = 2222
```

```bash
systemctl enable fail2ban
systemctl start fail2ban
```

### 3.8 Reconnect as Deploy User

From this point on, use the `deploy` user only:

```bash
# From your local machine
ssh deploy@YOUR_SERVER_IP -p 2222
```

---

## 4. Runtime Environment

> **Run as:** `deploy` user

### 4.1 ZSH Shell Setup

```bash
sudo apt install -y zsh

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Add plugins
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Enable plugins in ~/.zshrc
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting dirhistory history)/' ~/.zshrc

source ~/.zshrc
```

### 4.2 NVM & Node.js

```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Add to shell profile permanently
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc

# Install LTS and set as default
nvm install --lts
nvm alias default node

# Verify
node -v
npm -v
```

### 4.3 PNPM & PM2

```bash
npm install -g pnpm pm2

# Verify
pnpm -v
pm2 -v
```

### 4.4 PM2 Auto-Start on Reboot

```bash
# Generate systemd startup script
pm2 startup

# Copy and run the command it outputs, then:
pm2 save
```

> ⚠️ **Critical:** Without `pm2 startup && pm2 save`, all your apps go offline after every server reboot.

---

## 5. GitHub & Git Authentication

### Method 1: SSH Key (Recommended for VPS)

```bash
# Generate key (on server)
ssh-keygen -t ed25519 -C "vps-deploy-$(hostname)" -f ~/.ssh/id_ed25519

# Start SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Display public key — copy this entire output
cat ~/.ssh/id_ed25519.pub
```

Add to GitHub:
1. Go to **GitHub → Settings → SSH and GPG Keys → New SSH Key**
2. Title: `VPS Deploy - <your server hostname>`
3. Paste public key → Save

```bash
# Test connection
ssh -T git@github.com
# Expected: "Hi username! You've successfully authenticated..."

# Configure Git identity
git config --global user.email "your-email@example.com"
git config --global user.name "Your Name"

# Clone using SSH
git clone git@github.com:username/repository.git
```

### Method 2: GitHub CLI (HTTPS)

```bash
# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg --dearmor
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh -y

# Authenticate
gh auth login
# → GitHub.com → HTTPS → Yes → Login with a web browser

# Configure Git
git config --global user.email "your-email@example.com"
git config --global user.name "Your Name"
```

---

## 6. Environment Variables & Secrets Management

**Never store secrets in the repository, shell history, or world-readable files.**

### 6.1 Create and Secure `.env` Files

```bash
# Navigate to project
cd /var/www/your-project

# Create .env file
nano .env
# Paste your environment variables

# Lock down permissions immediately
chmod 600 .env
chown deploy:deploy .env

# Verify — should show -rw------- 1 deploy deploy
ls -la .env
```

### 6.2 Environment File Template

```ini
# /var/www/your-backend/.env
NODE_ENV=production
PORT=5001

# Database
DATABASE_URL=mongodb://appUser:strongPassword@localhost:27017/yourdb?replicaSet=rs0&authSource=admin

# Auth
JWT_SECRET=use-a-long-random-string-here
JWT_EXPIRES_IN=7d

# App
CORS_ORIGIN=https://your-frontend-domain.com
```

```ini
# /var/www/your-frontend/.env.local  (Next.js)
NODE_ENV=production
NEXT_PUBLIC_API_URL=https://api.your-domain.com
```

### 6.3 Prevent Accidental Secrets in Git

```bash
# Ensure .env is in .gitignore
echo ".env" >> .gitignore
echo ".env.local" >> .gitignore
echo ".env.production" >> .gitignore

# Check if .env was ever committed (run in repo root)
git log --all --full-history -- "**/.env*"
# If any results appear, rotate all secrets immediately
```

### 6.4 AWS Secrets Manager / SSM (AWS Deployments)

See [Section 15 — AWS EC2](#15-aws-ec2-specific-guide) for AWS-native secrets management using SSM Parameter Store.

---

## 7. Project Setup & Deployment

### 7.1 Directory Structure

```bash
sudo mkdir -p /var/www
sudo chown -R deploy:deploy /var/www
cd /var/www
```

### 7.2 Clone Repositories

```bash
# Backend
git clone git@github.com:your-username/your-backend.git
cd your-backend
chmod 600 .env   # after creating .env

# Frontend
cd /var/www
git clone git@github.com:your-username/your-frontend.git
```

### 7.3 Deploy Commands

**Backend (with Prisma/ORM):**

```bash
cd /var/www/your-backend
git pull origin main --ff-only              # fail if history diverged
pnpm install --frozen-lockfile              # exact versions from lockfile
pnpm prisma generate                        # update Prisma client
pnpm prisma migrate deploy                  # apply pending migrations
pnpm build
pm2 restart ecosystem.config.js --env production
sudo nginx -t && sudo systemctl reload nginx
```

**Backend (without Prisma):**

```bash
cd /var/www/your-backend
git pull origin main --ff-only
pnpm install --frozen-lockfile
pnpm build
pm2 restart ecosystem.config.js --env production
sudo nginx -t && sudo systemctl reload nginx
```

**Frontend (Next.js):**

```bash
cd /var/www/your-frontend
git pull origin main --ff-only
pnpm install --frozen-lockfile
pnpm build
pm2 restart ecosystem.config.js --env production
sudo nginx -t && sudo systemctl reload nginx
```

### 7.4 Verify Deployment

```bash
# Check all PM2 apps are online
pm2 list

# Check recent logs for errors
pm2 logs your-backend --lines 50

# Test health endpoint
curl -s https://api.your-domain.com/health

# Check Nginx is serving correctly
curl -I https://your-domain.com
```

---

## 8. MongoDB Setup

### 8.1 System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 1 GB | 2 GB+ |
| Disk | 2 GB free | 10 GB+ |
| OS | Ubuntu 22.04 | Ubuntu 22.04 LTS |

### 8.2 Install MongoDB 8.0

```bash
# Add MongoDB GPG key and repository
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
  | sudo gpg -o /usr/share/keyrings/mongodb-archive-keyring.gpg --dearmor

CODENAME=$(grep -E '^UBUNTU_CODENAME=' /etc/os-release | cut -d= -f2)
echo "deb [signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg] \
  https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/8.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list

sudo apt update
sudo apt install -y mongodb-org

# Create directories
sudo mkdir -p /var/lib/mongodb /var/log/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb
```

### 8.3 Configure MongoDB (Secure)

```bash
sudo tee /etc/mongod.conf > /dev/null <<'EOF'
storage:
  dbPath: /var/lib/mongodb

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

net:
  port: 27017
  bindIp: 127.0.0.1       # NEVER 0.0.0.0 — localhost only

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

replication:
  replSetName: rs0

security:
  authorization: enabled   # Require authentication
EOF
```

### 8.4 Start MongoDB and Initialize Replica Set

```bash
sudo systemctl enable --now mongod
sudo systemctl restart mongod
sleep 5

# Initialize replica set (no auth yet)
mongosh --quiet --eval '
  rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "localhost:27017" }]
  })
'

sleep 3   # Wait for PRIMARY election
```

### 8.5 Create Admin and App Users

```bash
mongosh --quiet <<'EOF'
use admin

db.createUser({
  user: "mongoAdmin",
  pwd: "REPLACE_WITH_STRONG_ADMIN_PASSWORD",
  roles: ["root"]
})

db.createUser({
  user: "appUser",
  pwd: "REPLACE_WITH_STRONG_APP_PASSWORD",
  roles: [
    { role: "readWrite", db: "your-database-name" }
  ]
})
EOF
```

```bash
# Restart with auth enabled
sudo systemctl restart mongod

# Test authentication
mongosh "mongodb://appUser:YOUR_APP_PASSWORD@localhost:27017/your-database-name?authSource=admin" \
  --eval "db.runCommand({ ping: 1 })"
```

### 8.6 Update Backend `.env`

```ini
DATABASE_URL=mongodb://appUser:YOUR_APP_PASSWORD@localhost:27017/your-database-name?replicaSet=rs0&authSource=admin
```

---

## 9. Nginx Reverse Proxy & SSL

### 9.1 Install Nginx and Certbot

```bash
sudo apt install -y nginx certbot python3-certbot-nginx

# Verify Nginx is running
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 9.2 Domain-Based Configuration (Recommended)

Create separate config files for each domain/subdomain.

**Backend API (`api.your-domain.com`):**

```bash
sudo tee /etc/nginx/conf.d/api.your-domain.com.conf > /dev/null <<'EOF'
# Rate limiting zone (defined once, applied per location)
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/m;

server {
    listen 80;
    listen [::]:80;
    server_name api.your-domain.com;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Hide Nginx version
    server_tokens off;

    location / {
        limit_req zone=api_limit burst=20 nodelay;

        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:5001/health;
        access_log off;
    }
}
EOF
```

**Frontend (`your-domain.com`):**

```bash
sudo tee /etc/nginx/conf.d/your-domain.com.conf > /dev/null <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com www.your-domain.com;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    server_tokens off;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF
```

### 9.3 Validate and Reload

```bash
sudo nginx -t         # Must say "syntax is ok" and "test is successful"
sudo nginx -s reload  # Graceful reload — no downtime
```

### 9.4 Issue SSL Certificates

```bash
# Frontend domain
sudo certbot --nginx \
  -d your-domain.com \
  -d www.your-domain.com \
  --email your@email.com \
  --agree-tos \
  --non-interactive

# Backend domain
sudo certbot --nginx \
  -d api.your-domain.com \
  --email your@email.com \
  --agree-tos \
  --non-interactive
```

Certbot will automatically update your Nginx configs with SSL directives.

### 9.5 Auto-Renewal with Nginx Reload

```bash
# Test renewal first
sudo certbot renew --dry-run

# The deploy hook ensures Nginx reloads after each renewal
# Add to crontab (certbot's timer may not reload Nginx by default)
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook 'nginx -s reload'") | crontab -

# Verify crontab
crontab -l
```

### 9.6 No Domain — IP-Only Configuration (Temporary Only)

Use this only during initial setup before DNS propagates. **Replace with domain config as soon as possible.**

```bash
sudo tee /etc/nginx/conf.d/default.conf > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_cache_bypass \$http_upgrade;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:5001/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo nginx -t && sudo nginx -s reload
```

---

## 10. PM2 Process Management

### 10.1 Backend Ecosystem Config

```javascript
// /var/www/your-backend/ecosystem.config.js
module.exports = {
  apps: [
    {
      name: "your-backend",
      script: "./dist/server.js",

      // Cluster mode uses all CPU cores
      instances: "max",
      exec_mode: "cluster",

      // Memory protection
      max_memory_restart: "400M",

      // Restart behavior
      restart_delay: 3000,
      max_restarts: 10,
      min_uptime: "10s",

      // Logging
      error_file: "/var/log/pm2/your-backend-error.log",
      out_file:   "/var/log/pm2/your-backend-out.log",
      merge_logs: true,
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",

      // Load env from .env file in production
      env_production: {
        NODE_ENV: "production",
      },
    },
  ],
};
```

### 10.2 Frontend Ecosystem Config

```javascript
// /var/www/your-frontend/ecosystem.config.js
module.exports = {
  apps: [
    {
      name: "your-frontend",
      script: "node_modules/next/dist/bin/next",
      args: "start",
      instances: 2,
      exec_mode: "cluster",
      max_memory_restart: "500M",
      error_file: "/var/log/pm2/your-frontend-error.log",
      out_file:   "/var/log/pm2/your-frontend-out.log",
      merge_logs: true,
      env_production: {
        NODE_ENV: "production",
        PORT: 3000,
      },
    },
  ],
};
```

### 10.3 Starting and Managing Apps

```bash
# Create PM2 log directory
sudo mkdir -p /var/log/pm2
sudo chown -R deploy:deploy /var/log/pm2

# Start
pm2 start ecosystem.config.js --env production

# Save process list for reboot persistence
pm2 save

# Essential commands
pm2 list                          # View all apps and status
pm2 logs your-backend             # Stream logs
pm2 logs your-backend --lines 100 # Last 100 lines
pm2 monit                         # Live CPU/memory dashboard
pm2 restart your-backend          # Restart one app
pm2 reload your-backend           # Zero-downtime reload (cluster mode)
pm2 stop your-backend             # Stop without deleting
pm2 delete your-backend           # Stop and remove from PM2
pm2 flush                         # Clear all log files
```

---

## 11. CI/CD Pipeline

### 11.1 GitHub Actions — Auto Deploy on Push

Create this file in your repository:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches:
      - main

jobs:
  deploy:
    name: SSH Deploy
    runs-on: ubuntu-latest
    environment: production       # Requires approval if configured

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host:     ${{ secrets.VPS_HOST }}
          port:     ${{ secrets.VPS_SSH_PORT }}   # e.g. 2222
          username: ${{ secrets.VPS_USER }}        # deploy
          key:      ${{ secrets.VPS_SSH_KEY }}     # private key content

          script: |
            set -e

            echo "→ Pulling latest code..."
            cd /var/www/your-backend
            git pull origin main --ff-only

            echo "→ Installing dependencies..."
            pnpm install --frozen-lockfile

            echo "→ Running database migrations..."
            pnpm prisma migrate deploy

            echo "→ Building..."
            pnpm build

            echo "→ Restarting PM2..."
            pm2 reload ecosystem.config.js --env production

            echo "→ Reloading Nginx..."
            sudo nginx -s reload

            echo "→ Health check..."
            sleep 3
            curl -sf https://api.your-domain.com/health || exit 1

            echo "✅ Deployment complete"
```

### 11.2 Required GitHub Secrets

Go to **GitHub → Repository → Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|--------|-------|
| `VPS_HOST` | Your server IP address |
| `VPS_SSH_PORT` | Your SSH port (e.g., `2222`) |
| `VPS_USER` | `deploy` |
| `VPS_SSH_KEY` | Private key (`cat ~/.ssh/id_ed25519` from your local machine) |

### 11.3 Allow `deploy` User to Reload Nginx Without Password

```bash
# On the server
sudo visudo
# Add this line at the bottom:
deploy ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload, /usr/sbin/nginx -t
```

---

## 12. Monitoring & Alerting

### 12.1 Uptime Monitoring (Free)

1. Create a free account at [UptimeRobot](https://uptimerobot.com) or [Better Uptime](https://betteruptime.com)
2. Add HTTP monitor for:
   - `https://your-domain.com` — Frontend
   - `https://api.your-domain.com/health` — Backend API
3. Set check interval: every 5 minutes
4. Enable alerts: Email + SMS/Slack on downtime

### 12.2 Add a `/health` Endpoint (Express)

```javascript
// src/routes/health.js
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV,
  });
});
```

### 12.3 Server Resource Monitoring

```bash
# Install netdata (free, lightweight, beautiful dashboard)
bash <(curl -Ss https://my-netdata.io/kickstart.sh)

# Access at: http://YOUR_SERVER_IP:19999
# Bind to localhost + tunnel for security:
ufw deny 19999    # Don't expose to internet
# Access via SSH tunnel: ssh -L 19999:localhost:19999 deploy@your-server
```

### 12.4 PM2 Live Dashboard

```bash
pm2 monit         # CPU, memory, logs per app — live
pm2 plus          # PM2's cloud dashboard (freemium)
```

---

## 13. Logging Strategy

### 13.1 Nginx Log Rotation

Nginx logs rotate automatically via `logrotate`. Verify:

```bash
cat /etc/logrotate.d/nginx
```

### 13.2 PM2 Log Rotation

```bash
# Install log rotation module
pm2 install pm2-logrotate

# Configure
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 14       # Keep 14 days
pm2 set pm2-logrotate:compress true
pm2 set pm2-logrotate:rotateInterval '0 0 * * *'   # Daily at midnight
```

### 13.3 View Logs

```bash
# Nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# PM2 (stream all apps)
pm2 logs

# PM2 (specific app, last 100 lines)
pm2 logs your-backend --lines 100

# MongoDB
sudo tail -f /var/log/mongodb/mongod.log

# System journal
sudo journalctl -u nginx -f
sudo journalctl -u mongod -f
```

### 13.4 Structured Application Logging

Use a logging library instead of `console.log`:

```bash
pnpm add pino pino-pretty
```

```javascript
// src/lib/logger.js
import pino from 'pino';

export const logger = pino({
  level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
  transport: process.env.NODE_ENV !== 'production'
    ? { target: 'pino-pretty' }
    : undefined,
});

// Usage
logger.info({ userId: '123' }, 'User logged in');
logger.error({ err }, 'Database connection failed');
```

---

## 14. Backup & Recovery

### 14.1 MongoDB Backup (Daily Cron)

```bash
# Create backup directory
sudo mkdir -p /var/backups/mongodb
sudo chown deploy:deploy /var/backups/mongodb

# Add to deploy user's crontab
crontab -e
```

Add these lines:

```cron
# Daily MongoDB backup at 2:00 AM
0 2 * * * mongodump \
  --uri="mongodb://appUser:YOUR_APP_PASSWORD@localhost:27017/your-database-name?authSource=admin" \
  --out="/var/backups/mongodb/$(date +\%Y-\%m-\%d)" \
  --gzip >> /var/log/mongodb-backup.log 2>&1

# Delete backups older than 7 days
30 2 * * * find /var/backups/mongodb -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
```

### 14.2 Restore from Backup

```bash
# List available backups
ls -la /var/backups/mongodb/

# Restore specific backup
mongorestore \
  --uri="mongodb://appUser:YOUR_APP_PASSWORD@localhost:27017/?authSource=admin" \
  --gzip \
  /var/backups/mongodb/2026-05-01/your-database-name
```

### 14.3 Offsite Backup to S3 / Backblaze B2 (Optional but Recommended)

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure (follow interactive prompts for your provider)
rclone config

# Add offsite sync to crontab
# 0 3 * * * rclone sync /var/backups/mongodb remote:your-bucket/mongodb-backups
```

### 14.4 Application Code Recovery

Your application code is always recoverable via Git. Protect your `.env` files separately:

```bash
# Encrypt and store .env backup (local machine only)
gpg --symmetric --cipher-algo AES256 /var/www/your-backend/.env
# Store the encrypted .env.gpg in a password manager or secure vault
```

---

## 15. AWS EC2 Specific Guide

### 15.1 Key Differences from VPS

| Concern | VPS (Ubuntu) | AWS EC2 |
|---------|-------------|---------|
| Firewall | UFW | Security Groups (primary) |
| SSH auth | SSH key + hardened sshd | EC2 Key Pair + optional SSM |
| SSL | Let's Encrypt + Certbot | ACM + ALB (recommended) |
| Secrets | `.env` (chmod 600) | SSM Parameter Store or Secrets Manager |
| Scaling | Manual | Auto Scaling Groups |
| DNS | External (Cloudflare, etc.) | Route 53 |
| Backups | cron + rclone | AWS Backup + S3 lifecycle policies |

### 15.2 Launch EC2 Instance

1. **AMI:** Ubuntu Server 22.04 LTS
2. **Instance type:** `t3.small` (minimum), `t3.medium` for MongoDB
3. **Key pair:** Create or use existing — download `.pem` file
4. **Security Group:** Allow inbound: SSH (22), HTTP (80), HTTPS (443) only
5. **Storage:** 20 GB gp3 (not gp2)
6. **Elastic IP:** Allocate and associate one (otherwise IP changes on stop)

```bash
# Connect to EC2
chmod 400 your-key.pem
ssh -i your-key.pem ubuntu@YOUR_ELASTIC_IP
```

### 15.3 EC2 Security Group Rules

In the AWS Console (EC2 → Security Groups → Edit inbound rules):

| Type | Protocol | Port | Source | Reason |
|------|----------|------|--------|--------|
| SSH | TCP | 22 | Your IP only | Admin access |
| HTTP | TCP | 80 | 0.0.0.0/0 | Let's Encrypt + redirect |
| HTTPS | TCP | 443 | 0.0.0.0/0 | Production traffic |

> ❌ No rules for 3000, 5001, 27017 — internal traffic only.

### 15.4 AWS SSM Parameter Store for Secrets

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Store secrets (run from local machine or CI)
aws ssm put-parameter \
  --name "/myapp/production/DATABASE_URL" \
  --value "mongodb://appUser:pass@localhost:27017/mydb?replicaSet=rs0" \
  --type "SecureString"

aws ssm put-parameter \
  --name "/myapp/production/JWT_SECRET" \
  --value "your-jwt-secret" \
  --type "SecureString"
```

Fetch secrets at deploy time:

```bash
# In your deploy script
export DATABASE_URL=$(aws ssm get-parameter \
  --name "/myapp/production/DATABASE_URL" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)
```

### 15.5 Route 53 DNS Setup

1. Go to **Route 53 → Hosted Zones → Create Hosted Zone**
2. Domain name: `your-domain.com`
3. Add records:

| Record | Type | Value |
|--------|------|-------|
| `your-domain.com` | A | Your Elastic IP |
| `www.your-domain.com` | CNAME | `your-domain.com` |
| `api.your-domain.com` | A | Your Elastic IP |

### 15.6 EC2 Initial Setup

Follow all steps in Sections 3–10 after connecting. Additionally:

```bash
# EC2-specific: create deploy user from ubuntu user
sudo adduser deploy
sudo usermod -aG sudo deploy
sudo cp -r ~/.ssh /home/deploy/
sudo chown -R deploy:deploy /home/deploy/.ssh

# EC2 Ubuntu default user is 'ubuntu', not 'root'
# After creating deploy user, reconnect as deploy
```

---

## 16. Troubleshooting Reference

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `Permission denied (publickey)` | SSH key not found | `cat ~/.ssh/id_ed25519.pub` → add to GitHub settings |
| SSH key bad permissions | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519` | |
| `502 Bad Gateway` | App not running or wrong port | `pm2 list` → check port in Nginx config matches ecosystem port |
| `404 Not Found` | Nginx config not reloaded | `sudo nginx -t && sudo nginx -s reload` |
| `pm2` app shows `errored` | App crash on start | `pm2 logs app-name --lines 50` |
| Out of memory / PM2 killed | RAM exhausted | `free -h` → `pm2 set pm2:max_memory_restart 400M` → add swap |
| `pnpm install` killed | OOM during install | Check swap: `swapon --show` → add if missing (Section 3.5) |
| `bcrypt` error | Native module mismatch | `npm rebuild bcrypt && pnpm i` |
| MongoDB auth failed | Wrong credentials in `.env` | Test: `mongosh "mongodb://user:pass@localhost/db?authSource=admin"` |
| `mongod` not starting | Config error or disk full | `systemctl status mongod` + `journalctl -u mongod -n 50` |
| Nginx config error | Syntax mistake | `sudo nginx -t` shows exact line |
| SSL cert expired | Renewal cron not running | `sudo certbot renew --dry-run` → check crontab |
| SSL cert not renewing | Port 80 blocked | `ufw allow 80/tcp` |
| `ENOSPC` (no space left) | Disk full | `df -h` → `sudo apt clean && sudo journalctl --vacuum-size=50M` |
| GitHub clone fails (private repo) | Auth not set up | Use `gh repo clone` or SSH method |
| `git pull` rejected (non-fast-forward) | Server has diverged | Never force-push to server; fix locally and redeploy |

---

## 17. Quick Reference Commands

### PM2

```bash
pm2 list                              # Status of all apps
pm2 logs                              # Stream all logs
pm2 logs <name> --lines 100           # Last 100 lines for one app
pm2 monit                             # Live dashboard
pm2 reload <name>                     # Zero-downtime restart (cluster mode)
pm2 restart ecosystem.config.js       # Restart from config file
pm2 save                              # Persist process list across reboots
pm2 flush                             # Clear all logs
```

### Nginx

```bash
sudo nginx -t                         # Test config syntax
sudo nginx -s reload                  # Graceful reload (no downtime)
sudo systemctl restart nginx          # Full restart
sudo systemctl status nginx           # Status
sudo nginx -T | grep server_name      # List all configured domains
cat /etc/nginx/conf.d/<domain>.conf   # View specific config
```

### MongoDB

```bash
sudo systemctl status mongod          # Service status
mongosh                               # Open shell (local)
mongosh "mongodb://user:pass@localhost/db?authSource=admin"   # Auth shell
mongodump --uri="..."                 # Manual backup
mongorestore --uri="..." /path        # Restore from backup
```

### System

```bash
df -h                                 # Disk usage
free -h                               # RAM + swap usage
htop                                  # Process monitor
lsof -i :5001                         # Which process owns port 5001
netstat -tulpn | grep LISTEN          # All listening ports
sudo ufw status verbose               # Firewall rules
uptime                                # System uptime + load
```

### Git on Server

```bash
# Always use --ff-only to avoid merge commits on server
git pull origin main --ff-only

# Check current branch and status
git status
git log --oneline -5
```

---

## 📊 Quick Reference — Stack Versions

| Component | Version | Notes |
|-----------|---------|-------|
| OS | Ubuntu 22.04 LTS | LTS until April 2027 |
| Node.js | v22.x LTS | Via NVM |
| PNPM | 9.x | `npm i -g pnpm` |
| PM2 | 5.x | `npm i -g pm2` |
| Nginx | 1.18+ | `apt install nginx` |
| MongoDB | 8.0 | Official repo |
| Certbot | Latest | `apt install certbot` |

---

## 🔐 Security Hardening Checklist

- [ ] Root login disabled (`PermitRootLogin no`)
- [ ] Password SSH auth disabled (`PasswordAuthentication no`)
- [ ] SSH on non-default port
- [ ] Fail2Ban installed and active
- [ ] UFW configured: only 22/80/443 open
- [ ] MongoDB bound to `127.0.0.1` only
- [ ] MongoDB authentication enabled
- [ ] `.env` files have `chmod 600`
- [ ] `.env` is in `.gitignore`
- [ ] Nginx serving with security headers
- [ ] Rate limiting on API routes
- [ ] `server_tokens off` in Nginx
- [ ] SSL certificates issued and auto-renewing
- [ ] Automatic security updates enabled
- [ ] PM2 apps have memory limits set
- [ ] `pm2 startup` and `pm2 save` run
- [ ] Backup cron is running and tested
- [ ] Uptime monitor configured with alerts

---

> 💡 **Deployment Rule of Thumb:** Always deploy to a staging environment first, run your test suite, then promote to production. Never deploy untested code directly to production.

---

**© 2026 Arman Mia. Production Deployment Guide — All rights reserved.**