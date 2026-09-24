# ============================================================
# CloudPulse - Compute module
# Creates: ECR repository (+ lifecycle policy), EC2 instance with Docker
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

# --- Pre-existing instance profile (AWS Academy: LabInstanceProfile -> LabRole) ---
# The Learner Lab denies iam:CreateRole, so a least-privilege role cannot be created here.
data "aws_iam_instance_profile" "lab" {
  name = var.instance_profile_name
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

# Tags are immutable commit SHAs, so images would pile up forever without this.
# Keeps the newest N images (enough to roll back several releases) and drops
# untagged leftovers after a day.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.ecr_images_to_keep} most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_images_to_keep
        }
        action = { type = "expire" }
      }
    ]
  })
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

  # Enforce IMDSv2 - mitigates SSRF-based credential theft
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
