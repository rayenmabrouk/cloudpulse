output "app_url" {
  description = "Public HTTPS URL (sslip.io hostname derived from the instance public IP)"
  value       = "https://${replace(module.compute.instance_public_ip, ".", "-")}.sslip.io"
}

output "instance_id" {
  description = "EC2 instance ID (target for SSM Run Command and Session Manager)"
  value       = module.compute.instance_id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance (changes when the Learner Lab restarts the instance)"
  value       = module.compute.instance_public_ip
}

output "ssm_session_command" {
  description = "Open a shell on the instance without SSH (requires the Session Manager plugin)"
  value       = "aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for image pushes"
  value       = module.compute.ecr_repository_url
}

output "backup_bucket_name" {
  description = "S3 bucket holding the daily SQLite backups"
  value       = module.compute.backup_bucket_name
}

output "secret_key_parameter_name" {
  description = "SSM Parameter Store name of the Django SECRET_KEY (the value is never output)"
  value       = module.compute.secret_key_parameter_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "app_security_group_id" {
  description = "Security group attached to the instance"
  value       = module.networking.app_security_group_id
}

output "ssh_enabled" {
  description = "Whether port 22 is open to allowed_ssh_cidr"
  value       = module.networking.ssh_enabled
}

output "log_group_name" {
  description = "CloudWatch log group for container logs (dpaste + Caddy)"
  value       = module.monitoring.log_group_name
}

output "alarm_names" {
  description = "CloudWatch alarms watching the deployment"
  value       = module.monitoring.alarm_names
}
