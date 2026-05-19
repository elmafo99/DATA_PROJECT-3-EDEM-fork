# 1. Create the secret container
resource "google_secret_manager_secret" "db_password_secret" {
  secret_id = "store-${var.environment}-db-password"

  replication {
    auto {}
  }
}

# 2. Store the password value inside the secret
resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password_secret.id
  secret_data = random_password.db_password.result
}

# Demo users password secret
resource "google_secret_manager_secret" "demo_password_secret" {
  secret_id = "store-${var.environment}-demo-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "demo_password_version" {
  secret      = google_secret_manager_secret.demo_password_secret.id
  secret_data = "Edem2526"
}