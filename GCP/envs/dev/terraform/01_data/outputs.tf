output "db_public_ip" {
  description = "Public IP of the Cloud SQL instance"
  value       = module.cloudsql_database.public_ip_address
}

output "db_user" {
  description = "Database username"
  value       = module.cloudsql_database.db_user
}

output "db_name" {
  description = "Database name"
  value       = module.cloudsql_database.db_name
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID for the DB password (read by Cloud Run at runtime)"
  value       = google_secret_manager_secret.db_password_secret.secret_id
}

output "db_instance_connection_name" {
  description = "Cloud SQL connection name used to mount the socket in Cloud Run"
  value       = module.cloudsql_database.instance_connection_name
}
