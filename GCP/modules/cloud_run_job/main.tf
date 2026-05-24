resource "google_cloud_run_v2_job" "job" {
  name                = var.job_name
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  template {
    template {
      service_account = var.service_account_email
      max_retries     = 1
      timeout         = "300s"

      dynamic "volumes" {
        for_each = length(var.cloud_sql_instances) > 0 ? [1] : []
        content {
          name = "cloudsql"
          cloud_sql_instance {
            instances = var.cloud_sql_instances
          }
        }
      }

      containers {
        image = var.image_url

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = var.secret_env_vars
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }

        dynamic "volume_mounts" {
          for_each = length(var.cloud_sql_instances) > 0 ? [1] : []
          content {
            name       = "cloudsql"
            mount_path = "/cloudsql"
          }
        }
      }
    }
  }
}
