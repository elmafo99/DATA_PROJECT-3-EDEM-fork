# =============================================================================
# DATABASE (CLOUD SQL - POSTGRESQL)
# =============================================================================

# Generate a random password
resource "random_password" "db_password" {
  length  = 32
  special = false
}

module "cloudsql_database" {
  source = "../../../../modules/cloudsql"

  project_id = var.project_id
  region     = var.region

  # Resource names
  instance_name = "store-postgres-instance-dev"
  db_name       = "store_db"
  db_user       = "store_admin"

  db_password   = random_password.db_password.result

  # Machine and disk configuration for DEV (cost saving)
  machine_tier  = "db-f1-micro"
  disk_size     = 10
  disk_type     = "PD_HDD"

  # Key for DEV: allows Terraform to destroy the entire database
  enable_deletion_protection = false

  # Resource labels
  labels = {
    environment = "dev"
    component   = "database"
  }
}