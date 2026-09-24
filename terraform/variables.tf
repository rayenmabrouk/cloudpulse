# ============================================================
# CloudPulse - Root variables
# Defaults match the AWS Academy Learner Lab this project runs in.
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources (the Learner Lab allows us-east-1 and us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource names and tags"
  type        = string
  default     = "cloudpulse"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name, used in tags"
  type        = string
  default     = "dev"
}

variable "allowed_ssh_cidr" {
  description = "Single IPv4 CIDR allowed to SSH (break-glass only; operations use SSM). Empty string = port 22 closed."
  type        = string
  default     = ""

  validation {
    condition     = var.allowed_ssh_cidr == "" || (can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0")
    error_message = "allowed_ssh_cidr must be empty (SSH disabled) or a valid CIDR such as 203.0.113.10/32. 0.0.0.0/0 is refused."
  }
}

variable "instance_type" {
  description = "EC2 instance type (the Learner Lab limits instance sizes)"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name (vockey is pre-created in the Learner Lab). Changing it replaces the instance."
  type        = string
  default     = "vockey"
}

variable "instance_profile_name" {
  description = "Existing IAM instance profile for the EC2 instance. The Learner Lab forbids creating IAM roles, so the pre-created LabInstanceProfile is used."
  type        = string
  default     = "LabInstanceProfile"
}

variable "ecr_images_to_keep" {
  description = "Number of most recent images kept in ECR; older ones are expired by a lifecycle policy"
  type        = number
  default     = 10

  validation {
    condition     = var.ecr_images_to_keep >= 2
    error_message = "Keep at least 2 images so the previous release stays available for rollback."
  }
}

variable "backup_retention_days" {
  description = "Days a SQLite backup is kept in the backup bucket before it expires"
  type        = number
  default     = 14
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for container logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "alarm_email" {
  description = "Email address notified when an alarm changes state (SNS). Empty string = no notifications."
  type        = string
  default     = ""
}
