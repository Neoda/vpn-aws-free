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
  description = "WireGuard server CIDR in tunnel"
  type        = string
  default     = "10.10.0.1/24"
}

variable "wg_clients" {
  description = "Map of WireGuard clients with their tunnel IPs"
  type = map(object({
    address = string
  }))
  default = {
    client1 = { address = "10.10.0.2/32" }
  }
}

variable "ssh_source_ip" {
  description = "Your IP for SSH access (CIDR). Restrict for security."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_source_ip, 0))
    error_message = "ssh_source_ip must be a valid CIDR block."
  }
}

variable "wg_easy_port" {
  description = "Port for wg-easy web UI"
  type        = number
  default     = 51821
}

variable "panel_3xui_port" {
  description = "Port for 3x-ui panel"
  type        = number
  default     = 2053
}

variable "netdata_port" {
  description = "Port for NetData monitoring dashboard"
  type        = number
  default     = 19999
}

variable "enable_netdata" {
  description = "Enable NetData monitoring"
  type        = bool
  default     = true
}
