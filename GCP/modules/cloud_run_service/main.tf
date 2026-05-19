resource "google_cloud_run_v2_service" "default" {
  name     = var.cloud_run_config.name
  location = var.cloud_run_config.location
  project  = var.project_id

  template {
    scaling {
      max_instance_count = var.cloud_run_config.max_instance_count
      min_instance_count = 0 
    }

    service_account = var.service_account_email
    
    containers {
      image = var.cloud_run_config.image
      ports {
        container_port = var.cloud_run_config.container_port
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  deletion_protection = false
}

# If allow_public_access is true, grants all users permission to invoke the service (unauthenticated)
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  count    = var.allow_public_access ? 1 : 0
  project  = var.project_id
  location = var.cloud_run_config.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}