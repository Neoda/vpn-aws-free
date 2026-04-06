# VPN Server on AWS Free Tier

Terraform configuration that deploys a full-featured VPN server on AWS free tier (t2.micro) with web management panels, monitoring, and security hardening.

## Services

| Service | Purpose | Port | Access |
|---------|---------|------|--------|
| **WireGuard** | Fast VPN tunnel | UDP 51820 | Public |
| **VLESS Reality (Xray)** | Censorship-resistant proxy | TCP 443 | Public |
| **Pi-hole** | DNS ad blocking | HTTP 80 | VPN only |
| **wg-easy** | WireGuard web management | TCP 51821 | VPN only |
| **3x-ui** | Xray/VLESS web panel | TCP 2053 | VPN only |
| **NetData** | Real-time monitoring | TCP 19999 | VPN only |

## Architecture

```
Internet
    |
[AWS Security Group] -- allow UDP 51820, TCP 443, TCP 22
    |
[EC2 t2.micro - Debian 12]
    |-- WireGuard (wg0: 10.10.0.1/24)
    |-- Xray/VLESS Reality
    |-- Pi-hole DNS
    |-- wg-easy (Docker)
    |-- 3x-ui panel
    |-- NetData
    |-- fail2ban
    |-- unattended-upgrades
    |
[VPN Tunnel 10.10.0.0/24]
    |-- Client 1 (10.10.0.2)
    |-- Client 2 (10.10.0.3)
    |-- Client N (10.10.0.N)
```

## AWS Free Tier

- Instance: t2.micro (1 vCPU, 1 GB RAM) - 750 hours/month for 12 months
- Storage: 30 GB gp3 EBS
- Network: 15 GB/month outbound
- Elastic IP: free while attached to running instance

## Quick Start

```bash
# 1. Auth with AWS
aws login

# 2. Clone and configure
git clone https://github.com/Neoda/vpn-aws-free.git
cd vpn-aws-free
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set your IP and client list

# 3. Deploy
terraform init
terraform apply

# 4. Get SSH key
terraform output -raw ssh_private_key > ssh_key
chmod 600 ssh_key

# 5. SSH into server (wait 5-10 min for full setup)
$(terraform output -raw ssh_command)

# 6. View all connection info on server
sudo cat /etc/vpn-info.txt
```

## Client Configuration

### WireGuard

```bash
# Get client config (replace CLIENT_NAME with your client name)
ssh -i ssh_key admin@<SERVER_IP> sudo cat /etc/wireguard/clients/CLIENT_NAME.conf

# Get QR code for mobile
ssh -i ssh_key admin@<SERVER_IP> sudo cat /etc/wireguard/clients/CLIENT_NAME-qr.txt
```

Import config into WireGuard client (Windows, macOS, iOS, Android, Linux).

### VLESS Reality

```bash
# Get VLESS connection link (import into v2ray client)
ssh -i ssh_key admin@<SERVER_IP> sudo cat /usr/local/etc/xray/vless-link.txt
```

Clients: v2rayN (Windows), v2rayNG (Android), Streisand (iOS), Nekoray (Linux).

## Web Panels (via VPN only)

Connect to WireGuard first, then access:

| Panel | URL | Credentials |
|-------|-----|-------------|
| wg-easy | `http://10.10.0.1:51821` | `terraform output -raw web_panels` |
| 3x-ui | `http://10.10.0.1:2053` | `terraform output -raw web_panels` |
| Pi-hole | `http://10.10.0.1/admin` | `sudo cat /etc/pihole/password.txt` |
| NetData | `http://10.10.0.1:19999` | No auth required |

## Multi-Client Support

Define clients in `terraform.tfvars`:

```hcl
wg_clients = {
  laptop  = { address = "10.10.0.2/32" }
  phone   = { address = "10.10.0.3/32" }
  tablet  = { address = "10.10.0.4/32" }
  friend  = { address = "10.10.0.5/32" }
}
```

Additional clients can be added via wg-easy web panel without Terraform.

## Security Features

- **fail2ban** - SSH brute-force protection (3 attempts, 2h ban)
- **SSH hardening** - key-only auth, no root login, max 3 attempts
- **Unattended upgrades** - automatic security patches
- **UFW firewall** - only VPN ports open publicly
- **VPC Flow Logs** - rejected traffic logged to CloudWatch
- **Panels behind VPN** - all management UIs accessible only via WireGuard
- **Health checks** - automatic service restart every 5 min
- **S3 encrypted state** - Terraform state with versioning and encryption

## Remote State Backend

After first `terraform apply`, migrate state to S3:

```bash
# Get bucket name
terraform output s3_state_bucket

# Uncomment backend block in main.tf, update bucket name, then:
terraform init -migrate-state
```

## Destroy

```bash
terraform destroy
```
