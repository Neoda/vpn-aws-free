#!/bin/bash
set -euo pipefail
exec > /var/log/startup-script.log 2>&1

echo "=== VPN Server Setup Starting ==="

# -----------------------------------------------
# Phase 1: System setup
# -----------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Enable IP forwarding
cat > /etc/sysctl.d/99-vpn.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
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
apt-get install -y curl wget gnupg lsb-release iptables ufw jq qrencode

# -----------------------------------------------
# Phase 2: WireGuard
# -----------------------------------------------
apt-get install -y wireguard wireguard-tools

# Generate server keys
WG_SERVER_PRIVATE=$(wg genkey)
WG_SERVER_PUBLIC=$(echo "$WG_SERVER_PRIVATE" | wg pubkey)

# Generate client keys
WG_CLIENT_PRIVATE=$(wg genkey)
WG_CLIENT_PUBLIC=$(echo "$WG_CLIENT_PRIVATE" | wg pubkey)

# Generate preshared key
WG_PRESHARED=$(wg genpsk)

# Detect primary interface
PRIMARY_IF=$(ip route show default | awk '{print $5}' | head -1)

# Server config
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

[Peer]
PublicKey = $WG_CLIENT_PUBLIC
PresharedKey = $WG_PRESHARED
AllowedIPs = ${wg_client_address}
EOF

chmod 600 /etc/wireguard/wg0.conf

# Get server external IP from AWS metadata (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
SERVER_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Client config
cat > /etc/wireguard/client.conf <<EOF
[Interface]
PrivateKey = $WG_CLIENT_PRIVATE
Address = ${wg_client_address}
DNS = 10.10.0.1

[Peer]
PublicKey = $WG_SERVER_PUBLIC
PresharedKey = $WG_PRESHARED
Endpoint = $SERVER_IP:${wg_port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/client.conf

# Generate QR code for mobile
qrencode -t ansiutf8 < /etc/wireguard/client.conf > /etc/wireguard/client-qr.txt 2>/dev/null || true

# Enable WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "=== WireGuard configured ==="

# -----------------------------------------------
# Phase 3: Xray / VLESS Reality
# -----------------------------------------------
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Generate x25519 key pair for Reality
XRAY_KEYS=$(/usr/local/bin/xray x25519)
REALITY_PRIVATE=$(echo "$XRAY_KEYS" | grep "Private" | awk '{print $3}')
REALITY_PUBLIC=$(echo "$XRAY_KEYS" | grep "Public" | awk '{print $3}')

# Save public key for client configuration
echo "$REALITY_PUBLIC" > /usr/local/etc/xray/public.key

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
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
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

# Generate VLESS share link
VLESS_LINK="vless://${vless_uuid}@$SERVER_IP:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$REALITY_PUBLIC&sid=${reality_short_id}&type=tcp#VPN-AWS"
echo "$VLESS_LINK" > /usr/local/etc/xray/vless-link.txt

systemctl enable xray
systemctl restart xray

echo "=== Xray VLESS Reality configured ==="

# -----------------------------------------------
# Phase 4: Pi-hole
# -----------------------------------------------
mkdir -p /etc/pihole

# Generate random password
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

# Install Pi-hole non-interactively
curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended || true

# Set password
pihole -a -p "$PIHOLE_PASS" || true

# Configure lighttpd to listen only on WireGuard interface
if [ -f /etc/lighttpd/lighttpd.conf ]; then
  echo 'server.bind = "10.10.0.1"' > /etc/lighttpd/external.conf
  systemctl restart lighttpd || true
fi

echo "=== Pi-hole configured ==="

# -----------------------------------------------
# Phase 5: Firewall (UFW)
# -----------------------------------------------
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow ${wg_port}/udp
ufw allow ${vless_port}/tcp
ufw allow in on wg0 to any port 53
ufw allow in on wg0 to any port 80
ufw --force enable

echo "=== Firewall configured ==="

# -----------------------------------------------
# Phase 6: Cron jobs for maintenance
# -----------------------------------------------
(crontab -l 2>/dev/null; echo "0 4 * * 0 systemctl restart xray") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 pihole -g") | crontab -

echo "=== Setup complete ==="
echo "Server IP: $SERVER_IP"
echo "WireGuard config: /etc/wireguard/client.conf"
echo "WireGuard QR: /etc/wireguard/client-qr.txt"
echo "VLESS link: /usr/local/etc/xray/vless-link.txt"
echo "VLESS public key: /usr/local/etc/xray/public.key"
echo "Pi-hole password: /etc/pihole/password.txt"
echo "Pi-hole admin: http://10.10.0.1/admin (via WireGuard)"
