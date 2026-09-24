# ============================================================
# CloudPulse - Terraform and provider configuration
# ============================================================

terraform {
  # >= 1.10 is required for S3-native state locking (use_lockfile in backend.tf)
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource: cost allocation, ownership, and a quick
  # way to tell Terraform-managed resources from console-created ones.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/rayenmabrouk/cloudpulse"
    }
  }
}
