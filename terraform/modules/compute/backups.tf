# ============================================================
# SQLite backups
# dpaste stores its data in SQLite on the instance's EBS volume. Without a copy
# elsewhere, losing the instance means losing every snippet. scripts/backup.sh
# (run daily by a systemd timer that deploy.sh installs) takes an online SQLite
# backup and uploads it here. Restore: scripts/backup.sh restore <key>.
# ============================================================

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "backups" {
  # checkov:skip=CKV_AWS_18:access logging needs a second log bucket; backups are written only by the instance role and every object is versioned
  # checkov:skip=CKV_AWS_144:cross-region replication needs an IAM replication role, which cannot be created in AWS Academy
  # checkov:skip=CKV_AWS_145:SSE-S3 (AES-256) encryption; a customer-managed KMS key adds cost with no benefit in a single-account lab
  # checkov:skip=CKV2_AWS_62:no consumer for event notifications
  bucket = "${var.project_name}-backups-${data.aws_caller_identity.current.account_id}"

  # Lab teardown must be able to delete the bucket with its objects.
  # In a real environment this would be false (and backups would be replicated).
  force_destroy = true

  tags = {
    Name = "${var.project_name}-backups"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

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
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
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
  bucket = aws_s3_bucket.backups.id
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
  value       = aws_s3_bucket.backups.bucket

  tags = {
    Name = "${var.project_name}-backup-bucket"
  }
}
