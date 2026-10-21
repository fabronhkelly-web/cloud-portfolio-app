# One environment = the same modules with different settings (see terraform.tfvars).

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  # Every resource gets these tags, so costs can be grouped by project and environment.
  default_tags {
    tags = {
      Project     = "cloud-portfolio-app"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "portfolio-${var.environment}"
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source = "../../modules/security"
  name   = local.name
  vpc_id = module.network.vpc_id
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "portfolio-app-${var.environment}"
}

module "database" {
  source                = "../../modules/database"
  name                  = local.name
  private_subnet_ids    = module.network.private_subnet_ids
  db_sg_id              = module.security.db_sg_id
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.deletion_protection
}

module "compute" {
  source               = "../../modules/compute"
  name                 = local.name
  environment          = var.environment
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  private_subnet_ids   = module.network.private_subnet_ids
  alb_sg_id            = module.security.alb_sg_id
  app_sg_id            = module.security.app_sg_id
  image_repository_url = module.ecr.repository_url
  desired_count        = var.desired_count
  max_count            = var.max_count
  db_host              = module.database.address
  db_port              = module.database.port
  db_name              = module.database.db_name
  db_secret_arn        = module.database.secret_arn
  deletion_protection  = var.deletion_protection
}

module "monitoring" {
  source                  = "../../modules/monitoring"
  name                    = local.name
  alert_email             = var.alert_email
  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  cluster_name            = module.compute.cluster_name
  service_name            = module.compute.service_name
  db_identifier           = module.database.identifier
}
