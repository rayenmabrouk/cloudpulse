# ============================================================
# SQLite backups
# dpaste stores its data in SQLite on the instance's EBS volume. Without a copy
# elsewhere, losing the instance means losing every snippet. scripts/backup.sh
# (run daily by a systemd timer that deploy.sh installs) takes an online SQLite
# backup and uploads it here. Restore: scripts/backup.sh restore <key>.
# ============================================================

data "aws_caller_identity" "current" {}

# The bucket itself is created by scripts/bootstrap-tfstate.ps1, not by Terraform:
# the AWS Academy service control policy denies s3:GetBucketObjectLockConfiguration,
# which the AWS provider calls every time it reads an aws_s3_bucket resource, so a
# Terraform-managed bucket fails on every plan. Everything that configures the bucket
# (public access block, versioning, encryption, lifecycle, TLS-only policy) is still
# managed here; none of those resources read the object-lock configuration.
# In a normal account this would simply be an aws_s3_bucket resource.
locals {
  backup_bucket     = "${var.project_name}-backups-${data.aws_caller_identity.current.account_id}"
  backup_bucket_arn = "arn:aws:s3:::${local.backup_bucket}"
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = local.backup_bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = local.backup_bucket

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = local.backup_bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = local.backup_bucket

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # Lifecycle rules on a versioned bucket must be created after versioning
  depends_on = [aws_s3_bucket_versioning.backups]
}

# Deny any request that is not made over TLS
data "aws_iam_policy_document" "backups_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.backup_bucket_arn,
      "${local.backup_bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = local.backup_bucket
  policy = data.aws_iam_policy_document.backups_tls_only.json

  # Applying a bucket policy while the public access block is being created can fail
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

# The backup script discovers the bucket through Parameter Store instead of
# hard-coding a naming convention.
resource "aws_ssm_parameter" "backup_bucket" {
  # checkov:skip=CKV2_AWS_34:bucket name is not a secret, a plain String parameter is intended
  name        = "/${var.project_name}/backup/bucket"
  description = "S3 bucket used by scripts/backup.sh"
  type        = "String"
  value       = local.backup_bucket

  tags = {
    Name = "${var.project_name}-backup-bucket"
  }
}
