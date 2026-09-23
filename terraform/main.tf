# ============================================================
# CloudPulse - Root Module
# Wires together: networking ? compute ? monitoring
# Infrastructure: Rayen Mabrouk
# ============================================================

module "networking" {
  source = "./modules/networking"

  project_name     = var.project_name
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "compute" {
  source = "./modules/compute"

  project_name      = var.project_name
  aws_region        = var.aws_region
  subnet_id         = module.networking.public_subnet_id
  security_group_id = module.networking.app_security_group_id
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  instance_id  = module.compute.instance_id
}
