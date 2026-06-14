locals {
  name_prefix = "${var.app_name}-${var.environment}"
  azs         = ["eu-north-1a", "eu-north-1b"]

  labels = {
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

# GCP_REPL_PASSWORD secret is created and rotated manually (see db-init/subscription/).
# Looked up by name rather than hardcoding the ARN suffix, which AWS regenerates
# whenever the secret is recreated.
data "aws_secretsmanager_secret" "gcp_repl_password" {
  name = "store-prod-gcp-repl-password"
}

module "network" {
  source = "../../../modules/network"

  name_prefix          = local.name_prefix
  azs                  = local.azs
  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
  labels               = local.labels
}

module "database" {
  source = "../../../modules/database"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids

  db_name = local.gcp_db_name
  db_user = local.gcp_db_user

  labels = local.labels
}

module "ecr" {
  source = "../../../modules/ecr"

  name_prefix      = local.name_prefix
  repository_names = ["api", "frontend", "db-init"]
  labels           = local.labels
}

module "compute" {
  source = "../../../modules/compute"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  api_image      = "${module.ecr.repository_urls["api"]}:latest"
  frontend_image = "${module.ecr.repository_urls["frontend"]}:latest"
  db_init_image  = "${module.ecr.repository_urls["db-init"]}:latest"

  deploy_frontend = var.deploy_frontend

  api_env_vars = {
    DB_HOST = module.database.address
    DB_USER = local.gcp_db_user
    DB_NAME = local.gcp_db_name
    DB_PORT = "5432"
  }

  api_secrets = {
    DB_PASSWORD = "${module.database.master_user_secret_arn}:password::"
  }

  db_init_env_vars = {
    DB_HOST = module.database.address
    DB_USER = local.gcp_db_user
    DB_NAME = local.gcp_db_name
    DB_PORT = "5432"
  }

  db_init_secrets = {
    DB_PASSWORD = "${module.database.master_user_secret_arn}:password::"
  }

  # Listed here so the shared ECS execution role can read it and so the
  # migration-sub task definition gets it injected.
  migration_secrets = {
    GCP_REPL_PASSWORD = data.aws_secretsmanager_secret.gcp_repl_password.arn
  }

  migration_sub_image = "${module.ecr.repository_urls["db-init"]}:subscription"

  migration_sub_env_vars = {
    DB_HOST  = module.database.address
    DB_USER  = local.gcp_db_user
    DB_NAME  = local.gcp_db_name
    DB_PORT  = "5432"
    GCP_HOST = local.gcp_db_public_ip
  }

  labels = local.labels
}
