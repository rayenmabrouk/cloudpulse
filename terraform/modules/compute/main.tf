# ============================================================
# CloudPulse ? Compute Module
# Creates: ECR repository, EC2 instance with Docker
# ============================================================

# --- Find latest Amazon Linux 2023 AMI ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Reference pre-existing Academy LabInstanceProfile ---
data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

# --- ECR Repository ---
resource "aws_ecr_repository" "app" {
  # checkov:skip=CKV_AWS_136:AES-256 encryption at rest; a customer-managed KMS key adds cost and key management with no benefit in a single-account lab
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

# --- EC2 Instance ---
resource "aws_instance" "app" {
  # checkov:skip=CKV_AWS_135:t3 instance types are EBS-optimized by default; the flag does not apply
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name
  key_name               = var.key_name
  monitoring             = true # 1-minute CloudWatch metrics for faster alarms

  # Enforce IMDSv2 ? prevents SSRF token theft
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-server"
  }
}
