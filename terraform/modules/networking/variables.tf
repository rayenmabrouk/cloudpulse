variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2"
  type        = string
}

variable "app_port" {
  description = "Application port exposed by the container"
  type        = number
  default     = 8000
}
