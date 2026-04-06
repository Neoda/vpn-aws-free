variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type (t2.micro for free tier)"
  type        = string
  default     = "t2.micro"
}

variable "vm_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "vpn-server"
}

variable "wg_port" {
  description = "WireGuard listen port"
  type        = number
  default     = 51820
}

variable "vless_port" {
  description = "VLESS Reality listen port"
  type        = number
  default     = 443
}

variable "wg_address" {
  description = "WireGuard server address in tunnel"
  type        = string
  default     = "10.10.0.1/24"
}

variable "wg_client_address" {
  description = "WireGuard client address in tunnel"
  type        = string
  default     = "10.10.0.2/32"
}

variable "ssh_source_ip" {
  description = "Your IP for SSH access (CIDR). Set to 0.0.0.0/0 for any."
  type        = string
  default     = "0.0.0.0/0"
}
