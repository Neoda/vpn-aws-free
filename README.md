# VPN Server on AWS Free Tier

Terraform configuration that deploys a full VPN server on AWS free tier (t2.micro).

## Services

- **WireGuard** - fast VPN tunnel (UDP 51820)
- **VLESS Reality (Xray)** - censorship-resistant proxy (TCP 443)
- **Pi-hole** - DNS-level ad blocking (accessible via WireGuard only)

## AWS Free Tier

- Instance: t2.micro (1 vCPU, 1 GB RAM) - 750 hours/month for 12 months
- Storage: 30 GB gp3 EBS
- Network: 15 GB/month outbound (free tier)
- Elastic IP: free while attached to running instance

## Quick Start

```bash
# 1. Auth with AWS
aws login

# 2. Init and deploy
cd vpn-gcp-free
terraform init
terraform apply

# 3. Get SSH key
terraform output -raw ssh_private_key > ssh_key
chmod 600 ssh_key

# 4. SSH into server (wait 3-5 min for startup script)
$(terraform output -raw ssh_command)

# 5. Get WireGuard client config
ssh -i ssh_key admin@<SERVER_IP> sudo cat /etc/wireguard/client.conf

# 6. Get WireGuard QR code (for mobile)
ssh -i ssh_key admin@<SERVER_IP> sudo cat /etc/wireguard/client-qr.txt

# 7. Get VLESS connection link
ssh -i ssh_key admin@<SERVER_IP> sudo cat /usr/local/etc/xray/vless-link.txt

# 8. Get Pi-hole password
ssh -i ssh_key admin@<SERVER_IP> sudo cat /etc/pihole/password.txt
```

## Client Setup

### WireGuard
Import `client.conf` into any WireGuard client (Windows, macOS, iOS, Android, Linux).

### VLESS Reality
Use the VLESS link from step 7 with: v2rayN (Windows), v2rayNG (Android), Streisand (iOS), Nekoray (Linux).

### Pi-hole
Accessible at `http://10.10.0.1/admin` when connected via WireGuard. DNS is automatically routed through Pi-hole.

## Destroy

```bash
terraform destroy
```
