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