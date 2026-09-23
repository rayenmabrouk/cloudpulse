# ============================================================
# CloudPulse — Root Variables
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "cloudpulse"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 (your IP)"
  type        = string
}
