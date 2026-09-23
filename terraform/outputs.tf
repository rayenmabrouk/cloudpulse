output "instance_public_ip" {
  description = "Public IP of the EC2 instance running dpaste"
  value       = module.compute.instance_public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker image push"
  value       = module.compute.ecr_repository_url
}

output "log_group_name" {
  description = "CloudWatch log group for container logs"
  value       = module.monitoring.log_group_name
}
