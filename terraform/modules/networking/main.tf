# ============================================================
# CloudPulse - Networking Module
# Creates: VPC, public subnet, internet gateway, route table,
#          security group
# ============================================================

# --- VPC ---
resource "aws_vpc" "main" {
  # checkov:skip=CKV2_AWS_11:VPC flow logs need a delivery IAM role, which cannot be created in AWS Academy; documented as a production requirement
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# --- Public Subnet ---
data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394:single-AZ deployment that only uses names[0]
  state = "available"
}

resource "aws_subnet" "public" {
  # checkov:skip=CKV_AWS_130:public subnet by design (no NAT gateway, for cost); production would use a private subnet behind a load balancer
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# --- Route Table ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ---
resource "aws_security_group" "app" {
  # checkov:skip=CKV_AWS_260:port 80 is required for the HTTP to HTTPS redirect and Let's Encrypt HTTP-01 validation
  # checkov:skip=CKV_AWS_382:outbound access needed for ECR, SSM, Let's Encrypt and OS packages; production would use VPC endpoints and restricted egress
  # checkov:skip=CKV2_AWS_5:false positive - attached to the EC2 instance in the compute module
  name        = "${var.project_name}-app-sg"
  description = "Security group for CloudPulse application"
  vpc_id      = aws_vpc.main.id

  # SSH - break-glass only, from a single CIDR, and only when allowed_ssh_cidr is set.
  # Normal operations (deploys, shell access) go through SSM, which needs no inbound port.
  dynamic "ingress" {
    for_each = var.allowed_ssh_cidr == "" ? [] : [var.allowed_ssh_cidr]
    content {
      description = "SSH from allowed IP (break-glass)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # HTTP - Caddy redirects to HTTPS and answers Let's Encrypt HTTP-01 challenges
  ingress {
    description = "HTTP redirect to HTTPS and ACME challenge"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS - public entry point; TLS terminated by Caddy on the instance
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# --- Default security group: all rules removed (nothing should use it) ---
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-default-sg-locked"
  }
}
