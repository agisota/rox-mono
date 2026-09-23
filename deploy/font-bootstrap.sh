#!/bin/bash
# Bootstrap font.rox.one on a Debian/Ubuntu node: opens the guest firewall,
# ensures sshd, installs nginx + self-signed TLS, deploys the site from GitHub main.
# Idempotent; runs as root via GCE startup-script metadata (or manually).
set -euo pipefail
exec > >(logger -t font-bootstrap) 2>&1

# --- guest firewall: this VM dropped all inbound; open ssh + web ---
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
  iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
  iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
fi

# --- sshd: make the box administrable again ---
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true

# --- site + nginx ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx curl openssl

mkdir -p /var/www /etc/ssl/font.rox.one

curl -fsSL https://codeload.github.com/agisota/rox-mono/tar.gz/refs/heads/main -o /tmp/rox-mono.tgz
rm -rf /tmp/rox-mono-main
tar -xzf /tmp/rox-mono.tgz -C /tmp

rm -rf /var/www/font.rox.one
cp -r /tmp/rox-mono-main/docs /var/www/font.rox.one
cp /tmp/rox-mono-main/deploy/font.rox.one.conf /etc/nginx/sites-available/font.rox.one.conf
ln -sf /etc/nginx/sites-available/font.rox.one.conf /etc/nginx/sites-enabled/font.rox.one.conf
rm -f /etc/nginx/sites-enabled/default

if [ ! -f /etc/ssl/font.rox.one/privkey.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/ssl/font.rox.one/privkey.pem \
    -out /etc/ssl/font.rox.one/fullchain.pem -days 825 \
    -subj "/CN=font.rox.one" -addext "subjectAltName=DNS:font.rox.one"
fi

nginx -t
systemctl enable nginx
systemctl restart nginx
