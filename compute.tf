# SSH key for access
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "vpn" {
  key_name   = "vpn-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

# UUID for VLESS
resource "random_uuid" "vless" {}

# Short ID for Reality
resource "random_id" "reality_short" {
  byte_length = 4
}

# Password for wg-easy
resource "random_password" "wg_easy" {
  length  = 16
  special = false
}

# Password for 3x-ui
resource "random_password" "panel_3xui" {
  length  = 16
  special = false
}

# Get latest Debian 12 AMI
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian official

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_instance" "vpn" {
  ami                    = data.aws_ami.debian.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.vpn.key_name
  vpc_security_group_ids = [aws_security_group.vpn.id]
  subnet_id              = aws_subnet.vpn.id

  source_dest_check = false # Required for VPN NAT

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/startup.sh.tpl", {
    wg_port            = var.wg_port
    wg_address         = var.wg_address
    wg_clients         = var.wg_clients
    vless_port         = var.vless_port
    vless_uuid         = random_uuid.vless.result
    reality_short_id   = random_id.reality_short.hex
    wg_easy_port       = var.wg_easy_port
    wg_easy_password   = random_password.wg_easy.result
    panel_3xui_port    = var.panel_3xui_port
    panel_3xui_password = random_password.panel_3xui.result
    netdata_port       = var.netdata_port
    enable_netdata     = var.enable_netdata
  })

  tags = { Name = var.vm_name }

  lifecycle {
    ignore_changes = [user_data]
  }
}
