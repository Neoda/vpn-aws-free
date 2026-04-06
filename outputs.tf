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

output "wireguard_client_config" {
  description = "WireGuard client configuration (retrieve from server after startup)"
  value       = <<-EOT
    # WireGuard client config will be generated on the server.
    # SSH into the server and run:  sudo cat /etc/wireguard/client.conf
    # Server IP: ${aws_eip.vpn.public_ip}
    # WireGuard port: ${var.wg_port}
  EOT
}

output "vless_connection" {
  description = "VLESS connection info"
  value       = <<-EOT
    # VLESS Reality connection details:
    # Address: ${aws_eip.vpn.public_ip}
    # Port: ${var.vless_port}
    # UUID: ${random_uuid.vless.result}
    # Flow: xtls-rprx-vision
    # Security: reality
    # SNI: www.microsoft.com
    # Short ID: ${random_id.reality_short.hex}
    # Public key: retrieve from server - ssh in and run: sudo cat /usr/local/etc/xray/public.key
  EOT
  sensitive = true
}

output "pihole_info" {
  description = "Pi-hole access info"
  value       = <<-EOT
    # Pi-hole is accessible ONLY via WireGuard VPN:
    # Web UI: http://10.10.0.1/admin
    # DNS: 10.10.0.1 (configured automatically in WireGuard client)
    # Password: retrieve from server - ssh in and run: sudo cat /etc/pihole/password.txt
  EOT
}
