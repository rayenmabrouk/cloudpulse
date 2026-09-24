variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7
}

variable "alarm_email" {
  description = "Email notified on alarm state changes; empty string = no SNS topic"
  type        = string
  default     = ""
}
