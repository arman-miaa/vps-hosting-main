


# VPS Hosting Full Deployment Guide

## 1. Linux Setup Configuration
**File:** `setup.sh`
```bash
vi setup.sh
# (Ctrl + Shift + V to paste the script)
# Save: ESC → :wq → Enter
ls
bash setup.sh
# When asked: "Do you want to change default shell to zsh?" → type: y
exit
```

---

## 2. Git User Setup
**File:** `git.sh`
```bash
vi git.sh
# Paste script → save (:wq)
bash git.sh
```
Setup Steps:
- q / a → Github.com
- HTTPS
- Yes
- Login with browser
- Visit: https://github.com/login/device
- Enter One-time code
- Email: `github@smtech24.com`
- Username: Your GitHub username

---

## 3. Project Folder Setup
```bash
mkdir /var/www
cd /var/www
pwd
# clone project
git clone https://...
cd project_name
cd ..
clear
```

---

## 4. Nginx Deployment (conf.d)
**From root folder:**
```bash
cd
vi deploy.sh
# paste → :wq
bash deploy.sh
```
Inputs:
- Backend port
- Domain name (NO http/https)
- Email (official recommended)

---

## 5. Verify Nginx Setup
```bash
cd /etc/nginx/conf.d
ls
cat file_name.conf

cd /var/www
ls
cd project_name
ls
```

### Common Commands
```bash
pnpm i && pnpm prisma generate && pnpm build && pm2 restart ecosystem.config.js && systemctl restart nginx
pnpm i && pnpm build && pm2 restart ecosystem.config.js && systemctl restart nginx
pm2 restart ecosystem.config.js && systemctl restart nginx
pm2 logs <number>
```

### bcrypt error fix
```bash
npm rebuild bcrypt
pnpm i
```

### Frontend deploy (from root)
```bash
cd
bash deploy.sh
# Provide frontend port + domain + email
```

---

## 6. Frontend Run Guide
```bash
cd /var/www
ls
cd frontend_name
# No prisma needed in frontend
```
If ecosystem file missing:
```bash
vi ecosystem.config.js
# paste config → save
pnpm i
```
SSL Fix:
```bash
sudo certbot -d domain.com -d www.domain.com
```

---

## 7. Local MongoDB Setup
**File:** `mongod.sh`
```bash
cd
vi mongod.sh
# paste → save (:wq)
```
Update `.env` with new MongoDB URL.

---

This guide contains all deployment commands and setup steps in file form.

