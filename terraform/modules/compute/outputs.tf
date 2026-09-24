output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "instance_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "backup_bucket_name" {
  description = "S3 bucket holding SQLite backups"
  value       = aws_s3_bucket.backups.bucket
}

output "secret_key_parameter_name" {
  description = "SSM parameter name of the Django SECRET_KEY"
  value       = aws_ssm_parameter.django_secret_key.name
}
