# ============================================================
# CloudPulse - Root module
# Wires together: networking -> compute -> monitoring
# ============================================================

module "networking" {
  source = "./modules/networking"

  project_name     = var.project_name
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  subnet_id             = module.networking.public_subnet_id
  security_group_id     = module.networking.app_security_group_id
  instance_type         = var.instance_type
  key_name              = var.ssh_key_name
  instance_profile_name = var.instance_profile_name
  ecr_images_to_keep    = var.ecr_images_to_keep
  backup_retention_days = var.backup_retention_days
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name       = var.project_name
  instance_id        = module.compute.instance_id
  log_retention_days = var.log_retention_days
  alarm_email        = var.alarm_email
}
