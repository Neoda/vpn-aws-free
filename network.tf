resource "aws_vpc" "vpn" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "vpn-vpc" }
}

resource "aws_internet_gateway" "vpn" {
  vpc_id = aws_vpc.vpn.id
  tags   = { Name = "vpn-igw" }
}

resource "aws_subnet" "vpn" {
  vpc_id                  = aws_vpc.vpn.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = { Name = "vpn-subnet" }
}

resource "aws_route_table" "vpn" {
  vpc_id = aws_vpc.vpn.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpn.id
  }

  tags = { Name = "vpn-rt" }
}

resource "aws_route_table_association" "vpn" {
  subnet_id      = aws_subnet.vpn.id
  route_table_id = aws_route_table.vpn.id
}

resource "aws_eip" "vpn" {
  domain = "vpc"
  tags   = { Name = "vpn-eip" }
}

resource "aws_eip_association" "vpn" {
  instance_id   = aws_instance.vpn.id
  allocation_id = aws_eip.vpn.id
}

# VPC Flow Logs for security monitoring
resource "aws_flow_log" "vpn" {
  vpc_id          = aws_vpc.vpn.id
  traffic_type    = "REJECT"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/vpc/vpn-flow-logs"
  retention_in_days = 7

  tags = { Name = "vpn-flow-logs" }
}

resource "aws_iam_role" "flow_log" {
  name = "vpn-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "vpn-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_security_group" "vpn" {
  name        = "vpn-sg"
  description = "VPN server security group"
  vpc_id      = aws_vpc.vpn.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_source_ip]
  }

  # WireGuard
  ingress {
    description = "WireGuard"
    from_port   = var.wg_port
    to_port     = var.wg_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # VLESS Reality
  ingress {
    description = "VLESS Reality"
    from_port   = var.vless_port
    to_port     = var.vless_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP
  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vpn-sg" }
}
