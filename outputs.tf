output "server_ip" {
  description = "Elastic IP of the VPN server"
  value       = aws_eip.vpn.public_ip
}

output "ssh_private_key" {
  description = "SSH private key to connect to the server"
  value       = tls_private_key.ssh.private_key_openssh
  sensitive   = true
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ssh_key admin@${aws_eip.vpn.public_ip}"
}

output "wireguard_info" {
  description = "WireGuard client configs location"
  value       = <<-EOT
    # WireGuard clients: ${join(", ", keys(var.wg_clients))}
    # Retrieve configs via SSH:
    %{for name, _ in var.wg_clients~}
    #   ${name}: sudo cat /etc/wireguard/clients/${name}.conf
    #   ${name} QR: sudo cat /etc/wireguard/clients/${name}-qr.txt
    %{endfor~}
    # Server: ${aws_eip.vpn.public_ip}:${var.wg_port}
  EOT
}

output "vless_connection" {
  description = "VLESS connection info"
  value       = <<-EOT
    # VLESS Reality:
    # Address: ${aws_eip.vpn.public_ip}
    # Port: ${var.vless_port}
    # UUID: ${random_uuid.vless.result}
    # Flow: xtls-rprx-vision
    # Security: reality
    # SNI: www.microsoft.com
    # Short ID: ${random_id.reality_short.hex}
    # Public key: sudo cat /usr/local/etc/xray/public.key
  EOT
  sensitive = true
}

output "web_panels" {
  description = "Web management panels (accessible via WireGuard VPN only)"
  value       = <<-EOT
    # All panels accessible ONLY when connected via WireGuard:
    #
    # wg-easy (WireGuard management):
    #   URL: http://10.10.0.1:${var.wg_easy_port}
    #   Password: ${random_password.wg_easy.result}
    #
    # 3x-ui (Xray/VLESS management):
    #   URL: http://10.10.0.1:${var.panel_3xui_port}
    #   User: admin
    #   Password: ${random_password.panel_3xui.result}
    #
    # Pi-hole (DNS ad blocking):
    #   URL: http://10.10.0.1/admin
    #   Password: retrieve via SSH - sudo cat /etc/pihole/password.txt
    #
    # NetData (monitoring):
    #   URL: http://10.10.0.1:${var.netdata_port}
    #
    # Full info on server: sudo cat /etc/vpn-info.txt
  EOT
  sensitive = true
}

output "s3_state_bucket" {
  description = "S3 bucket for Terraform state (for backend migration)"
  value       = aws_s3_bucket.tfstate.bucket
}
