# =============================================================================
# CLOUD SQL MODULE — Creates PostgreSQL Instance, Database and User
# =============================================================================

resource "google_sql_database_instance" "instance" {
  name             = var.instance_name
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_15" # Recommended for current PostGIS support

  deletion_protection = var.enable_deletion_protection

  settings {
    tier = var.machine_tier # e.g. "db-f1-micro" for dev (cheapest tier)

    # Disk configuration
    disk_size       = var.disk_size
    disk_type       = var.disk_type
    disk_autoresize = true

    # Enable public IP so local machines can connect during development
    ip_configuration {
      ipv4_enabled = true
    }

    user_labels = var.labels
  }
}

# Empty logical database inside the server
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.instance.name
  project  = var.project_id
}

# Admin user
resource "google_sql_user" "user" {
  name     = var.db_user
  instance = google_sql_database_instance.instance.name
  project  = var.project_id
  password = var.db_password
}