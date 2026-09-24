# CloudPulse - one-time bootstrap of the S3 buckets Terraform cannot create itself.
#  1. Terraform remote state bucket: Terraform cannot keep its state in a bucket
#     it has not created yet.
#  2. SQLite backup bucket: the AWS Academy service control policy denies
#     s3:GetBucketObjectLockConfiguration, which the AWS provider needs to manage an
#     aws_s3_bucket resource. Only the bucket is created here; its versioning,
#     encryption, lifecycle, TLS-only policy and public access block are managed
#     by Terraform (terraform/modules/compute/backups.tf).
# Idempotent: safe to re-run.
# Run: powershell -ExecutionPolicy Bypass -File scripts\bootstrap-tfstate.ps1
param([string]$Region = "us-east-1")

function Invoke-Aws {
    & aws @args
    if ($LASTEXITCODE -ne 0) { throw "aws $($args -join ' ') failed" }
}

$account = (aws sts get-caller-identity --query Account --output text).Trim()
$bucket  = "cloudpulse-tfstate-$account"
Write-Host "State bucket: $bucket"

aws s3api head-bucket --bucket $bucket *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-Aws s3api create-bucket --bucket $bucket --region $Region | Out-Null
    Write-Host "Created bucket"
} else {
    Write-Host "Bucket already exists"
}

# Versioning: every state write is kept; a bad apply can be rolled back
Invoke-Aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled

# Encryption at rest (SSE-S3). State contains secrets (e.g. the Django SECRET_KEY).
Invoke-Aws s3api put-bucket-encryption --bucket $bucket --server-side-encryption-configuration "Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256},BucketKeyEnabled=true}]"

# No public access, ever
Invoke-Aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Deny any request not made over TLS
$policy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
"@
$policyFile = Join-Path $env:TEMP "cloudpulse-tfstate-policy.json"
[System.IO.File]::WriteAllText($policyFile, $policy)
Invoke-Aws s3api put-bucket-policy --bucket $bucket --policy "file://$policyFile"
Remove-Item $policyFile

Write-Host "Bucket $bucket ready: versioned, encrypted, public access blocked, TLS-only."

# --- SQLite backup bucket (configuration is applied by Terraform) ---
$backupBucket = "cloudpulse-backups-$account"
aws s3api head-bucket --bucket $backupBucket *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-Aws s3api create-bucket --bucket $backupBucket --region $Region | Out-Null
    Write-Host "Created bucket $backupBucket (run terraform apply to configure it)"
} else {
    Write-Host "Bucket $backupBucket already exists"
}
