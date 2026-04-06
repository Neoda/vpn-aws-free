#!/bin/bash
set -euo pipefail
exec > /var/log/startup-script.log 2>&1

echo "=== VPN Server Setup Starting $(date) ==="

# -----------------------------------------------
# Phase 1: System setup
# -----------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Enable IP forwarding & BBR
cat > /etc/sysctl.d/99-vpn.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
SYSCTL
sysctl --system

# Create 1GB swap
if [ ! -f /swapfile ]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Install base packages
apt-get install -y curl wget gnupg lsb-release iptables ufw jq qrencode \
  apt-transport-https ca-certificates software-properties-common \
  docker.io docker-compose unattended-upgrades fail2ban

# Enable Docker
systemctl enable docker
systemctl start docker

echo "=== Phase 1: System setup complete ==="

# -----------------------------------------------
# Phase 2: Security hardening
# -----------------------------------------------

# --- fail2ban ---
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 3
bantime = 7200
F2B
systemctl enable fail2ban
systemctl restart fail2ban

# --- SSH hardening ---
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
systemctl restart sshd

# --- Unattended upgrades ---
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'UPG'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
UPG

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UPG2'
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
UPG2

systemctl enable unattended-upgrades

echo "=== Phase 2: Security hardening complete ==="

# -----------------------------------------------
# Phase 3: WireGuard
# -----------------------------------------------
apt-get install -y wireguard wireguard-tools

# Generate server keys
WG_SERVER_PRIVATE=$(wg genkey)
WG_SERVER_PUBLIC=$(echo "$WG_SERVER_PRIVATE" | wg pubkey)

# Detect primary interface
PRIMARY_IF=$(ip route show default | awk '{print $5}' | head -1)

# Get server external IP from AWS metadata (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
SERVER_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Build server config with multiple clients
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${wg_address}
ListenPort = ${wg_port}
PrivateKey = $WG_SERVER_PRIVATE

PostUp = iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $PRIMARY_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
EOF

# Generate configs for each client
mkdir -p /etc/wireguard/clients

%{ for name, client in wg_clients ~}
# Client: ${name}
CLIENT_PRIVATE_${name}=$(wg genkey)
CLIENT_PUBLIC_${name}=$(echo "$CLIENT_PRIVATE_${name}" | wg pubkey)
CLIENT_PSK_${name}=$(wg genpsk)

# Add peer to server config
cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
# ${name}
PublicKey = $CLIENT_PUBLIC_${name}
PresharedKey = $CLIENT_PSK_${name}
AllowedIPs = ${client.address}
EOF

# Generate client config file
cat > /etc/wireguard/clients/${name}.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_${name}
Address = ${client.address}
DNS = 10.10.0.1

[Peer]
PublicKey = $WG_SERVER_PUBLIC
PresharedKey = $CLIENT_PSK_${name}
Endpoint = $SERVER_IP:${wg_port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/clients/${name}.conf
qrencode -t ansiutf8 < /etc/wireguard/clients/${name}.conf > /etc/wireguard/clients/${name}-qr.txt 2>/dev/null || true

%{ endfor ~}

chmod 600 /etc/wireguard/wg0.conf

# Symlink first client as default
FIRST_CLIENT=$(ls /etc/wireguard/clients/*.conf 2>/dev/null | head -1)
if [ -n "$FIRST_CLIENT" ]; then
  cp "$FIRST_CLIENT" /etc/wireguard/client.conf
  chmod 600 /etc/wireguard/client.conf
fi

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "=== Phase 3: WireGuard configured (${length(wg_clients)} clients) ==="

# -----------------------------------------------
# Phase 4: Xray / VLESS Reality
# -----------------------------------------------
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Generate x25519 key pair for Reality
XRAY_KEYS=$(/usr/local/bin/xray x25519)
REALITY_PRIVATE=$(echo "$XRAY_KEYS" | grep "Private" | awk '{print $3}')
REALITY_PUBLIC=$(echo "$XRAY_KEYS" | grep "Public" | awk '{print $3}')

echo "$REALITY_PRIVATE" > /usr/local/etc/xray/private.key
echo "$REALITY_PUBLIC" > /usr/local/etc/xray/public.key
chmod 600 /usr/local/etc/xray/private.key

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": ${vless_port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${vless_uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com",
            "microsoft.com"
          ],
          "privateKey": "$REALITY_PRIVATE",
          "shortIds": [
            "${reality_short_id}",
            ""
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

mkdir -p /var/log/xray

# Generate VLESS share link
VLESS_LINK="vless://${vless_uuid}@$SERVER_IP:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$REALITY_PUBLIC&sid=${reality_short_id}&type=tcp#VPN-AWS"
echo "$VLESS_LINK" > /usr/local/etc/xray/vless-link.txt

systemctl enable xray
systemctl restart xray

echo "=== Phase 4: Xray VLESS Reality configured ==="

# -----------------------------------------------
# Phase 5: Pi-hole
# -----------------------------------------------
mkdir -p /etc/pihole

PIHOLE_PASS=$(openssl rand -base64 12)
echo "$PIHOLE_PASS" > /etc/pihole/password.txt
chmod 600 /etc/pihole/password.txt

cat > /etc/pihole/setupVars.conf <<EOF
PIHOLE_INTERFACE=wg0
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=1000
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSMASQ_LISTENING=local
WEBPASSWORD=
BLOCKING_ENABLED=true
PIHOLE_DNS_1=1.1.1.1
PIHOLE_DNS_2=8.8.8.8
REV_SERVER=false
EOF

curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended || true
pihole -a -p "$PIHOLE_PASS" || true

if [ -f /etc/lighttpd/lighttpd.conf ]; then
  echo 'server.bind = "10.10.0.1"' > /etc/lighttpd/external.conf
  systemctl restart lighttpd || true
fi

echo "=== Phase 5: Pi-hole configured ==="

# -----------------------------------------------
# Phase 6: wg-easy (WireGuard Web UI)
# -----------------------------------------------
docker run -d \
  --name wg-easy \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  -e WG_HOST="$SERVER_IP" \
  -e PASSWORD_HASH="$(echo -n '${wg_easy_password}' | openssl dgst -sha256 -hex | awk '{print $2}')" \
  -e WG_PORT="${wg_port}" \
  -e WG_DEFAULT_DNS="10.10.0.1" \
  -e WG_ALLOWED_IPS="0.0.0.0/0, ::/0" \
  -e WG_PERSISTENT_KEEPALIVE="25" \
  -e PORT="${wg_easy_port}" \
  -p 127.0.0.1:${wg_easy_port}:${wg_easy_port}/tcp \
  -v /etc/wireguard:/etc/wireguard \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  ghcr.io/wg-easy/wg-easy:latest || true

echo "=== Phase 6: wg-easy configured (port ${wg_easy_port} via VPN) ==="

# -----------------------------------------------
# Phase 7: 3x-ui (Xray Panel)
# -----------------------------------------------
cd /tmp
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<XPANEL
y
XPANEL

# Configure 3x-ui to listen only on localhost (accessible via WireGuard)
if command -v x-ui &>/dev/null; then
  x-ui setting -port ${panel_3xui_port} || true
  x-ui setting -username admin -password '${panel_3xui_password}' || true
  systemctl restart x-ui || true
fi

echo "=== Phase 7: 3x-ui configured (port ${panel_3xui_port} via VPN) ==="

# -----------------------------------------------
# Phase 8: NetData monitoring
# -----------------------------------------------
%{ if enable_netdata ~}
curl -fsSL https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh
bash /tmp/netdata-kickstart.sh --dont-wait --no-updates --stable-channel || true

# Bind NetData only to WireGuard interface
if [ -f /etc/netdata/netdata.conf ]; then
  sed -i 's/# bind to = \*/bind to = 10.10.0.1/' /etc/netdata/netdata.conf
  systemctl restart netdata || true
fi

echo "=== Phase 8: NetData configured (port ${netdata_port} via VPN) ==="
%{ else ~}
echo "=== Phase 8: NetData skipped (disabled) ==="
%{ endif ~}

# -----------------------------------------------
# Phase 9: Firewall (UFW)
# -----------------------------------------------
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow ${wg_port}/udp
ufw allow ${vless_port}/tcp
# Services accessible only via WireGuard tunnel
ufw allow in on wg0 to any port 53
ufw allow in on wg0 to any port 80
ufw allow in on wg0 to any port ${wg_easy_port}
ufw allow in on wg0 to any port ${panel_3xui_port}
ufw allow in on wg0 to any port ${netdata_port}
ufw --force enable

echo "=== Phase 9: Firewall configured ==="

# -----------------------------------------------
# Phase 10: Health checks & cron
# -----------------------------------------------

# Systemd watchdog for services
cat > /usr/local/bin/vpn-healthcheck.sh <<'HEALTH'
#!/bin/bash
FAILED=""
systemctl is-active --quiet wg-quick@wg0 || { systemctl restart wg-quick@wg0; FAILED="$FAILED wireguard"; }
systemctl is-active --quiet xray || { systemctl restart xray; FAILED="$FAILED xray"; }
if [ -n "$FAILED" ]; then
  echo "$(date) - Restarted:$FAILED" >> /var/log/vpn-healthcheck.log
fi
HEALTH
chmod +x /usr/local/bin/vpn-healthcheck.sh

# Cron jobs
cat > /etc/cron.d/vpn-maintenance <<'CRON'
# Health check every 5 minutes
*/5 * * * * root /usr/local/bin/vpn-healthcheck.sh
# Restart Xray weekly (memory leak mitigation)
0 4 * * 0 root systemctl restart xray
# Update Pi-hole gravity weekly
0 3 * * 0 root pihole -g > /dev/null 2>&1
# Clean old logs monthly
0 0 1 * * root journalctl --vacuum-time=7d
CRON

echo "=== Phase 10: Health checks & cron configured ==="

# -----------------------------------------------
# Summary
# -----------------------------------------------
cat > /etc/vpn-info.txt <<SUMMARY
=== VPN Server Info ===
Server IP: $SERVER_IP
Setup completed: $(date)

--- WireGuard ---
Port: ${wg_port}
Clients: $(ls /etc/wireguard/clients/*.conf 2>/dev/null | wc -l)
Configs: /etc/wireguard/clients/

--- VLESS Reality ---
Port: ${vless_port}
Link: /usr/local/etc/xray/vless-link.txt
Public Key: /usr/local/etc/xray/public.key

--- Pi-hole ---
Web UI: http://10.10.0.1/admin (via VPN)
Password: /etc/pihole/password.txt

--- wg-easy ---
Web UI: http://10.10.0.1:${wg_easy_port} (via VPN)
Password: ${wg_easy_password}

--- 3x-ui Panel ---
Web UI: http://10.10.0.1:${panel_3xui_port} (via VPN)
User: admin
Password: ${panel_3xui_password}

--- NetData ---
Dashboard: http://10.10.0.1:${netdata_port} (via VPN)

--- SSH ---
ssh -i ssh_key admin@$SERVER_IP
SUMMARY

chmod 600 /etc/vpn-info.txt

echo "=== VPN Server Setup Complete $(date) ==="
echo "All services info: cat /etc/vpn-info.txt"
