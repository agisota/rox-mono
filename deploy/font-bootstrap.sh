#!/bin/bash
# Bootstrap font.rox.one on a Debian node: tear down the guest firewall that
# drops ALL inbound, ensure sshd, install nginx + self-signed TLS, deploy the
# site from GitHub main. Idempotent; runs as root via GCE startup-script metadata.
set -uo pipefail
exec > >(logger -t font-bootstrap) 2>&1

# --- beacon: proves this script ran (readable via guest attributes) ---
curl -s -m 5 -X PUT --data "ran-$(date -u +%FT%TZ)" \
  -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/guest-attributes/font-bootstrap/status" || true

# --- firewall: this VM drops ALL inbound incl. ICMP; bring the filters down ---
command -v ufw >/dev/null 2>&1 && ufw disable || true
systemctl disable --now nftables 2>/dev/null || true
systemctl disable --now firewalld 2>/dev/null || true
command -v nft >/dev/null 2>&1 && nft flush ruleset || true
if command -v iptables >/dev/null 2>&1; then
  iptables -P INPUT ACCEPT || true
  iptables -F INPUT || true
  iptables -P FORWARD ACCEPT || true
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
