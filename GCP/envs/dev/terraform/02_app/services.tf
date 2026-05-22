# =============================================================================
# API — Cloud Run (FastAPI)
# =============================================================================

module "api_service" {
  source     = "../../../../modules/cloud_run_service"
  project_id = var.project_id

  cloud_run_config = {
    name               = "${var.app_name}-api-${var.environment}"
    location           = var.region
    image              = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}-${var.environment}/api:latest"
    container_port     = 8000
    max_instance_count = 3
  }

  service_account_email = data.terraform_remote_state.base.outputs.app_sa_email
  allow_public_access   = true

  # DB_HOST uses the Cloud SQL socket path — no public IP needed
  env_vars = {
    DB_HOST      = "/cloudsql/${data.terraform_remote_state.data.outputs.db_instance_connection_name}"
    DB_USER      = data.terraform_remote_state.data.outputs.db_user
    DB_NAME      = data.terraform_remote_state.data.outputs.db_name
    DB_PORT      = "5432"
    CORS_ORIGINS = module.frontend_service.service_url
  }

  secret_env_vars = {
    DB_PASSWORD = data.terraform_remote_state.data.outputs.db_password_secret_id
  }

  cloud_sql_instances = [data.terraform_remote_state.data.outputs.db_instance_connection_name]
}

# =============================================================================
# FRONTEND — Cloud Run (Nginx + React)
# =============================================================================

module "frontend_service" {
  source     = "../../../../modules/cloud_run_service"
  project_id = var.project_id

  cloud_run_config = {
    name               = "${var.app_name}-frontend-${var.environment}"
    location           = var.region
    image              = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}-${var.environment}/frontend:latest"
    container_port     = 80
    max_instance_count = 3
  }

  service_account_email = data.terraform_remote_state.base.outputs.app_sa_email
  allow_public_access   = true
}
