# Remote state in S3 (bucket bootstrapped by scripts/bootstrap-tfstate.ps1):
# versioned, SSE-S3 encrypted, public access blocked, TLS-only bucket policy.
# use_lockfile = S3-native state locking (Terraform >= 1.10); no DynamoDB table needed.
#
# Backend blocks cannot use variables. The bucket name contains the AWS account ID;
# to use another account, override it at init time instead of editing this file:
#   terraform init -backend-config="bucket=cloudpulse-tfstate-<account-id>"
terraform {
  backend "s3" {
    bucket       = "cloudpulse-tfstate-530008597446"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
