variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name (changing it replaces the instance)"
  type        = string
  default     = "vockey"
}

variable "instance_profile_name" {
  description = "Existing IAM instance profile attached to the instance"
  type        = string
  default     = "LabInstanceProfile"
}

variable "ecr_images_to_keep" {
  description = "Number of most recent images kept in ECR"
  type        = number
  default     = 10
}

variable "backup_retention_days" {
  description = "Days a SQLite backup object is kept"
  type        = number
  default     = 14
}
