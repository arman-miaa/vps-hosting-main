# 🚀 GitHub Actions CI/CD Deployment Guide

> **Author:** Arman Mia  
> **Last Updated:** 02 June 2026  
> **Stack:** GitHub Actions, Self-Hosted Runner, VPS, PM2, Nginx  

---

## 📑 Table of Contents

1. [Overview & Architecture](#1-overview--architecture)
2. [GitHub Self-Hosted Runner Setup](#2-github-self-hosted-runner-setup)
3. [GitHub Actions Workflow Files](#3-github-actions-workflow-files)
4. [Environment Secrets & Variables](#4-environment-secrets--variables)
5. [Complete Workflow Examples](#5-complete-workflow-examples)
6. [Testing & Troubleshooting](#6-testing--troubleshooting)
7. [Advanced Configurations](#7-advanced-configurations)

---

## 1. Overview & Architecture

### 🎯 What This Does

```
You Push Code → GitHub Actions Triggers → Self-Hosted Runner on VPS Executes → Auto Deploy → Live Site Updated
```

### 🏗️ Architecture Flow

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Git Push   │────▶│  GitHub Actions   │────▶│  VPS Server  │
│  (main/dev) │     │  Workflow Trigger │     │  (Runner)    │
└─────────────┘     └──────────────────┘     └─────────────┘
                            │                        │
                            ▼                        ▼
                    ┌──────────────┐         ┌──────────────┐
                    │  Build/Test   │         │  PM2 Restart │
                    │  Deploy Steps │────────▶│  Nginx Reload│
                    └──────────────┘         └──────────────┘
```

### 📋 Prerequisites

| Requirement | Details |
|:---|:---|
| **VPS** | Ubuntu 22.04+ with Node.js, PM2, Nginx installed |
| **GitHub** | Repository with admin access |
| **Runner** | Self-hosted GitHub Actions runner on VPS |
| **Disk Space** | At least 2GB free for runner + builds |
| **RAM** | Minimum 1GB (2GB recommended) |

---

## 2. GitHub Self-Hosted Runner Setup

### 📝 Method 1: Repository-Level Runner (Recommended)

```bash
# Step 1: SSH into your VPS
ssh root@your_vps_ip -p your_port

# Step 2: Create runner directory
mkdir -p /home/actions-runner && cd /home/actions-runner

# Step 3: Download the latest runner package
curl -o actions-runner-linux-x64-2.319.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz

# Step 4: Optional - Validate the hash
echo "3f6efb7488a183e291fc2c62876e14c9ee732864173734facc85a1bfb1744464  actions-runner-linux-x64-2.319.1.tar.gz" | shasum -a 256 -c

# Step 5: Extract the installer
tar xzf ./actions-runner-linux-x64-2.319.1.tar.gz

# Step 6: Configure the runner
./config.sh --url https://github.com/YOUR_USERNAME/YOUR_REPO --token YOUR_TOKEN_HERE

# ⚠️ Token পাওয়ার নিয়ম:
# 1. GitHub Repo → Settings → Actions → Runners → New self-hosted runner
# 2. Linux নির্বাচন করুন
# 3. Token copy করুন (token শুধু একবার দেখা যায়!)
```

### 🔧 Interactive Configuration Prompts

| Question | Answer |
|:---|:---|
| **Enter the name of the runner group** | Press Enter (default) |
| **Enter the name of the runner** | `vps-prod-runner` (or any name) |
| **Enter any additional labels** | `production,backend,nodejs` |
| **Enter name of work folder** | Press Enter (default: `_work`) |

```bash
# Step 7: Install runner as a service (auto-start on boot)
sudo ./svc.sh install

# Step 8: Start the runner service
sudo ./svc.sh start

# Step 9: Check runner status
sudo ./svc.sh status
```

### 📝 Method 2: Organization-Level Runner (Multiple Repos)

```bash
# Same steps as above, but use organization URL:
./config.sh --url https://github.com/YOUR_ORG_NAME --token YOUR_TOKEN_HERE

# Runner will be available for ALL repos in the organization
```

### 🔧 Runner Management Commands

```bash
# Check runner status
sudo ./svc.sh status

# Start runner
sudo ./svc.sh start

# Stop runner
sudo ./svc.sh stop

# Restart runner
sudo ./svc.sh restart

# Uninstall runner service
sudo ./svc.sh uninstall

# Remove runner completely
./config.sh remove --token YOUR_REMOVAL_TOKEN
# Token পাওয়ার নিয়ম: Repo Settings → Actions → Runners → Runner select → Remove → Copy token
```

### 📊 Verify Runner is Active

```bash
# GitHub এ চেক করুন:
# Repo → Settings → Actions → Runners
# Status: "Idle" বা "Active" দেখাবে
```

---

## 3. GitHub Actions Workflow Files

### 📁 File Structure

```
your-repo/
├── .github/
│   ├── workflows/
│   │   ├── deploy-backend.yml      # Backend deployment
│   │   ├── deploy-frontend.yml     # Frontend deployment
│   │   └── deploy-staging.yml      # Staging environment
│   └── dependabot.yml              # (optional)
├── ecosystem.config.js             # PM2 config (project root)
└── ...
```

### 🎯 Workflow Triggers

```yaml
# Push to specific branches
on:
  push:
    branches: [main, master]

# Pull request (preview deployments)
on:
  pull_request:
    branches: [main]

# Manual trigger from GitHub UI
on:
  workflow_dispatch:

# Scheduled deployments
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
```

---

## 4. Environment Secrets & Variables

### 🔐 Add Secrets to GitHub

```
GitHub Repo → Settings → Secrets and variables → Actions → New repository secret
```

### 📋 Required Secrets

| Secret Name | Description | Example |
|:---|:---|:---|
| `VPS_HOST` | VPS IP address | `123.456.789.0` |
| `VPS_USERNAME` | SSH username | `root` |
| `VPS_PORT` | SSH port | `22` |
| `VPS_SSH_KEY` | Private SSH key | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `ENV_FILE` | Production .env content | `DATABASE_URL=...` |
| `SLACK_WEBHOOK` | (Optional) Slack notifications | `https://hooks.slack.com/...` |

### 🔑 Generate SSH Key for Deployment

```bash
# On your VPS:
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions_deploy
# No passphrase (empty)

# Add public key to authorized_keys
cat ~/.ssh/github_actions_deploy.pub >> ~/.ssh/authorized_keys

# Copy PRIVATE key for GitHub Secret
cat ~/.ssh/github_actions_deploy
# Copy ENTIRE output (including -----BEGIN... and -----END...)
```

### 📝 Add Variables (Non-Secret)

```
GitHub Repo → Settings → Secrets and variables → Actions → Variables
```

| Variable Name | Description | Example |
|:---|:---|:---|
| `APP_NAME` | PM2 app name | `project-server` |
| `DEPLOY_PATH` | Project path on VPS | `/var/www/backend` |
| `NODE_VERSION` | Node.js version | `20` |

---

## 5. Complete Workflow Examples

### 🟢 Backend Deployment (Express/Node.js + PM2)

**File:** `.github/workflows/deploy-backend.yml`

```yaml
name: 🚀 Deploy Backend to VPS

on:
  push:
    branches: [main, master]
    paths:
      - 'src/**'           # Only trigger when source changes
      - 'package.json'
      - 'pnpm-lock.yaml'
      - 'ecosystem.config.js'
      - '.github/workflows/deploy-backend.yml'
  workflow_dispatch:        # Manual trigger from GitHub UI

env:
  NODE_VERSION: '20'
  APP_NAME: 'project-server'
  DEPLOY_PATH: '/var/www/backend'

jobs:
  deploy:
    name: 🎯 Deploy to Production
    runs-on: self-hosted     # YOUR VPS RUNNER
    # runs-on: [self-hosted, production, backend]  # With labels
    
    steps:
      # Step 1: Checkout code
      - name: 📥 Checkout Repository
        uses: actions/checkout@v4
        with:
          clean: true
          fetch-depth: 0

      # Step 2: Setup Node.js
      - name: ⚙️ Setup Node.js ${{ env.NODE_VERSION }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'pnpm'

      # Step 3: Setup PNPM
      - name: 📦 Setup PNPM
        uses: pnpm/action-setup@v2
        with:
          version: latest
          run_install: false

      # Step 4: Get PNPM store directory
      - name: 📁 Get PNPM Store Path
        id: pnpm-cache
        shell: bash
        run: |
          echo "STORE_PATH=$(pnpm store path)" >> $GITHUB_OUTPUT

      # Step 5: Setup PNPM cache
      - name: 🗃️ Setup PNPM Cache
        uses: actions/cache@v4
        with:
          path: ${{ steps.pnpm-cache.outputs.STORE_PATH }}
          key: ${{ runner.os }}-pnpm-store-${{ hashFiles('**/pnpm-lock.yaml') }}
          restore-keys: |
            ${{ runner.os }}-pnpm-store-

      # Step 6: Install dependencies
      - name: 📥 Install Dependencies
        run: pnpm install --frozen-lockfile --prefer-offline

      # Step 7: Generate Prisma Client (if using Prisma)
      - name: 🗄️ Generate Prisma Client
        run: pnpm prisma generate
        continue-on-error: true  # Skip if no Prisma

      # Step 8: Build project
      - name: 🔨 Build Project
        run: pnpm build
        env:
          NODE_ENV: production

      # Step 9: Copy files to deployment directory
      - name: 📋 Copy Build Files
        run: |
          # Create backup of current deployment
          if [ -d "${{ env.DEPLOY_PATH }}" ]; then
            cp -r ${{ env.DEPLOY_PATH }} ${{ env.DEPLOY_PATH }}_backup_$(date +%Y%m%d_%H%M%S)
          fi
          
          # Sync files (rsync style)
          rsync -av --delete \
            --exclude='node_modules' \
            --exclude='.git' \
            --exclude='.env' \
            --exclude='*.log' \
            ./ ${{ env.DEPLOY_PATH }}/

      # Step 10: Create .env file from GitHub Secret
      - name: 🔐 Setup Environment Variables
        run: |
          echo "${{ secrets.ENV_FILE }}" > ${{ env.DEPLOY_PATH }}/.env
          chmod 600 ${{ env.DEPLOY_PATH }}/.env

      # Step 11: Install production dependencies in deploy folder
      - name: 📦 Install Production Dependencies
        run: |
          cd ${{ env.DEPLOY_PATH }}
          pnpm install --frozen-lockfile --prod --prefer-offline

      # Step 12: Run database migrations (if needed)
      - name: 🗄️ Run Database Migrations
        run: |
          cd ${{ env.DEPLOY_PATH }}
          pnpm prisma migrate deploy
        continue-on-error: true

      # Step 13: Restart PM2 application
      - name: 🔄 Restart PM2 Application
        run: |
          cd ${{ env.DEPLOY_PATH }}
          
          # Check if PM2 app exists
          if pm2 list | grep -q "${{ env.APP_NAME }}"; then
            echo "Restarting existing app..."
            pm2 restart ${{ env.APP_NAME }} --update-env
          else
            echo "Starting new app..."
            pm2 start ecosystem.config.js
          fi
          
          # Save PM2 process list
          pm2 save

      # Step 14: Reload Nginx
      - name: 🌐 Reload Nginx
        run: |
          sudo nginx -t && sudo systemctl reload nginx
          echo "✅ Nginx reloaded successfully"

      # Step 15: Health Check
      - name: 🏥 Health Check
        run: |
          sleep 5  # Wait for app to start
          curl -f http://localhost:3000/api/health || true
          pm2 status

      # Step 16: Cleanup old backups (keep last 3)
      - name: 🧹 Cleanup Old Backups
        run: |
          cd $(dirname ${{ env.DEPLOY_PATH }})
          ls -t ${DEPLOY_PATH}_backup_* 2>/dev/null | tail -n +4 | xargs rm -rf || true

      # Step 17: Notify success (Slack example - optional)
      - name: 📢 Notify Deployment
        if: success()
        run: |
          echo "✅ Deployment successful!"
          # Uncomment for Slack notifications
          # curl -X POST -H 'Content-type: application/json' \
          #   --data '{"text":"✅ Backend deployed successfully!"}' \
          #   ${{ secrets.SLACK_WEBHOOK }}
```

### 🔵 Frontend Deployment (Next.js/React)

**File:** `.github/workflows/deploy-frontend.yml`

```yaml
name: 🎨 Deploy Frontend to VPS

on:
  push:
    branches: [main, master]
    paths:
      - 'app/**'
      - 'components/**'
      - 'public/**'
      - 'package.json'
      - 'pnpm-lock.yaml'
      - 'next.config.*'
      - '.github/workflows/deploy-frontend.yml'
  workflow_dispatch:

env:
  NODE_VERSION: '20'
  APP_NAME: 'project-client'
  DEPLOY_PATH: '/var/www/frontend'

jobs:
  deploy:
    name: 🎯 Deploy Frontend
    runs-on: self-hosted
    
    steps:
      - name: 📥 Checkout Repository
        uses: actions/checkout@v4

      - name: ⚙️ Setup Node.js ${{ env.NODE_VERSION }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'pnpm'

      - name: 📦 Setup PNPM
        uses: pnpm/action-setup@v2
        with:
          version: latest

      - name: 📥 Install Dependencies
        run: pnpm install --frozen-lockfile

      - name: 🔨 Build Next.js
        run: |
          pnpm build
        env:
          NODE_ENV: production
          NEXT_PUBLIC_API_URL: ${{ vars.NEXT_PUBLIC_API_URL }}

      - name: 📋 Deploy Build Files
        run: |
          # Create fresh deploy
          mkdir -p ${{ env.DEPLOY_PATH }}
          
          # Copy only necessary files
          rsync -av \
            --exclude='.git' \
            --exclude='node_modules' \
            --exclude='.env*' \
            .next/ package.json pnpm-lock.yaml ecosystem.config.js \
            ${{ env.DEPLOY_PATH }}/
          
          # Create .env for runtime
          echo "NODE_ENV=production" > ${{ env.DEPLOY_PATH }}/.env
          echo "NEXT_PUBLIC_API_URL=${{ vars.NEXT_PUBLIC_API_URL }}" >> ${{ env.DEPLOY_PATH }}/.env

      - name: 📦 Install Production Deps
        run: |
          cd ${{ env.DEPLOY_PATH }}
          pnpm install --frozen-lockfile --prod

      - name: 🔄 Restart PM2
        run: |
          cd ${{ env.DEPLOY_PATH }}
          pm2 restart ${{ env.APP_NAME }} || pm2 start ecosystem.config.js
          pm2 save

      - name: 🌐 Reload Nginx
        run: sudo nginx -t && sudo systemctl reload nginx

      - name: 🏥 Verify Deployment
        run: |
          sleep 3
          curl -I http://localhost:3000 || true
```

### 🟡 Monorepo Deployment (Frontend + Backend)

**File:** `.github/workflows/deploy-fullstack.yml`

```yaml
name: 🚀 Deploy Full Stack (Monorepo)

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  NODE_VERSION: '20'

jobs:
  # Detect which packages changed
  detect-changes:
    runs-on: self-hosted
    outputs:
      backend: ${{ steps.filter.outputs.backend }}
      frontend: ${{ steps.filter.outputs.frontend }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |
            backend:
              - 'packages/backend/**'
            frontend:
              - 'packages/frontend/**'

  # Deploy Backend (if changed)
  deploy-backend:
    needs: detect-changes
    if: needs.detect-changes.outputs.backend == 'true'
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'pnpm'
      - uses: pnpm/action-setup@v2
        with:
          version: latest
      
      - name: Deploy Backend
        run: |
          cd packages/backend
          pnpm install --frozen-lockfile
          pnpm build
          # ... copy, restart PM2, etc.

  # Deploy Frontend (if changed)
  deploy-frontend:
    needs: detect-changes
    if: needs.detect-changes.outputs.frontend == 'true'
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'pnpm'
      - uses: pnpm/action-setup@v2
        with:
          version: latest
      
      - name: Deploy Frontend
        run: |
          cd packages/frontend
          pnpm install --frozen-lockfile
          pnpm build
          # ... copy, restart PM2, etc.
```

---

## 6. Testing & Troubleshooting

### ✅ Test Your Workflow

```bash
# Method 1: Push to trigger branch
git add .
git commit -m "test: trigger deployment"
git push origin main

# Method 2: Manual trigger from GitHub
# Repo → Actions → Select Workflow → Run workflow
```

### 🔍 Check Workflow Logs

```
GitHub Repo → Actions → Click on workflow run → Check each step's output
```

### 📊 Common Issues & Solutions

| Issue | Cause | Solution |
|:---|:---|:---|
| **Runner offline** | Service stopped | `sudo ./svc.sh status` → `sudo ./svc.sh start` |
| **Permission denied** | Wrong file permissions | `sudo chown -R $USER:$USER /var/www` |
| **PNPM not found** | Missing global install | `npm install -g pnpm` on VPS |
| **Build fails** | Memory limit | Add `NODE_OPTIONS: --max-old-space-size=1024` |
| **PM2 app not restarting** | Wrong ecosystem path | Check `cd $DEPLOY_PATH` in workflow |
| **Nginx reload fails** | Syntax error | `sudo nginx -t` on VPS manually |
| **Env vars missing** | GitHub Secrets not set | Check Settings → Secrets |
| **Runner disk full** | Build artifacts piling up | Clean `_work` folder: `rm -rf /home/actions-runner/_work/*` |

### 🧹 Cleanup Runner Workspace

```bash
# Clean GitHub Actions work directory (free disk space)
rm -rf /home/actions-runner/_work/*

# Clean PNPM cache
pnpm store prune

# Clean Docker (if using)
docker system prune -af

# Check disk usage
df -h
```

---

## 7. Advanced Configurations

### 🔒 Multiple Environments (Staging + Production)

```yaml
name: 🚀 Deploy to Multiple Environments

on:
  push:
    branches:
      - staging    # → Staging environment
      - main       # → Production environment

jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    runs-on: [self-hosted, staging]
    environment: staging
    steps:
      # ... deploy to /var/www/staging with staging .env

  deploy-production:
    if: github.ref == 'refs/heads/main'
    runs-on: [self-hosted, production]
    environment: production
    steps:
      # ... deploy to /var/www/production with prod .env
```

### 🔄 Rollback Workflow

**File:** `.github/workflows/rollback.yml`

```yaml
name: ⏪ Rollback Deployment

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to rollback'
        required: true
        type: choice
        options:
          - production
          - staging

jobs:
  rollback:
    runs-on: self-hosted
    steps:
      - name: Find Latest Backup
        run: |
          cd /var/www
          LATEST_BACKUP=$(ls -t ${ENV}_backup_* 2>/dev/null | head -1)
          if [ -z "$LATEST_BACKUP" ]; then
            echo "❌ No backup found!"
            exit 1
          fi
          echo "Rolling back to: $LATEST_BACKUP"
          
      - name: Restore Backup
        run: |
          rm -rf /var/www/${{ github.event.inputs.environment }}
          cp -r $LATEST_BACKUP /var/www/${{ github.event.inputs.environment }}
          
      - name: Restart Services
        run: |
          pm2 restart ${{ env.APP_NAME }}
          sudo systemctl reload nginx
```

### 📢 Discord/Slack/Telegram Notifications

```yaml
# Add this step at the end of your workflow
- name: 📢 Send Discord Notification
  if: always()
  uses: sarisia/actions-status-discord@v1
  with:
    webhook: ${{ secrets.DISCORD_WEBHOOK }}
    title: "🚀 Deployment ${{ job.status }}"
    description: |
      **Repository:** ${{ github.repository }}
      **Branch:** ${{ github.ref_name }}
      **Commit:** ${{ github.sha }}
      **Status:** ${{ job.status }}
    color: ${{ job.status == 'success' && '0x00FF00' || '0xFF0000' }}
```

### 🐳 Docker-Based Deployment (Alternative)

```yaml
name: 🐳 Docker Deploy

on:
  push:
    branches: [main]

jobs:
  docker-deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Docker Image
        run: docker build -t my-app:${{ github.sha }} .
      
      - name: Stop Old Container
        run: docker stop my-app || true
      
      - name: Run New Container
        run: |
          docker run -d --name my-app \
            -p 3000:3000 \
            --restart always \
            my-app:${{ github.sha }}
      
      - name: Cleanup Old Images
        run: docker image prune -af
```

---

## 📊 Complete VPS Runner Setup Checklist

```bash
# ✅ 1. Basic VPS setup done (Node.js, PNPM, PM2, Nginx)
node -v    # Check Node.js
pnpm -v    # Check PNPM
pm2 -v     # Check PM2
nginx -v   # Check Nginx

# ✅ 2. GitHub Runner installed
sudo ./svc.sh status
# Output: "active (running)"

# ✅ 3. SSH key configured for deployment
cat ~/.ssh/github_actions_deploy.pub
# Must be in ~/.ssh/authorized_keys

# ✅ 4. Deployment directories ready
ls /var/www/
# backend/ frontend/ etc.

# ✅ 5. PM2 ecosystem files exist
cat /var/www/backend/ecosystem.config.js

# ✅ 6. GitHub Secrets configured
# Repo → Settings → Secrets and variables → Actions
# VPS_SSH_KEY, ENV_FILE, etc.

# ✅ 7. Test manual trigger
# GitHub → Actions → Select workflow → Run workflow
```

---

## 🎯 Quick Workflow Summary

| Trigger | Action | Result |
|:---|:---|:---|
| `git push origin main` | Backend workflow runs | Backend auto-deployed |
| `git push origin main` (frontend files) | Frontend workflow runs | Frontend auto-deployed |
| Manual trigger | Selected workflow runs | Manual deployment |
| `git push origin staging` | Staging workflow runs | Staging environment updated |
| Rollback trigger | Rollback workflow runs | Previous version restored |

---

## 🔐 Security Best Practices

```yaml
# Always use secrets for sensitive data
env:
  DATABASE_URL: ${{ secrets.DATABASE_URL }}
  JWT_SECRET: ${{ secrets.JWT_SECRET }}

# Never hardcode credentials
# ❌ BAD
run: echo "DATABASE_URL=mongodb://admin:password@localhost/db" > .env

# ✅ GOOD
run: echo "${{ secrets.ENV_FILE }}" > .env
```

---

> 💡 **Pro Tip:** First time setup-এর পর একটা test push করে দেখে নিন সব ঠিকমতো কাজ করছে কিনা। Runner status সবসময় "Idle" থাকা উচিত।

**মনে রাখবেন:** GitHub Actions-এর ফ্রি টায়ারে পাবলিক রিপোর জন্য Unlimited minutes, কিন্তু প্রাইভেট রিপোর জন্য monthly 2000 minutes limit আছে। Self-hosted runner ব্যবহার করলে এই limit প্রযোজ্য নয়!

---

**© 2026 Arman Mia. All rights reserved.**