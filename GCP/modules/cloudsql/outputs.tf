output "instance_connection_name" {
  description = "Instance connection name (required for Dataflow or Cloud SQL Proxy)"
  value       = google_sql_database_instance.instance.connection_name
}

output "public_ip_address" {
  description = "Public IP address to connect from DBeaver/DataGrip"
  value       = google_sql_database_instance.instance.public_ip_address
}

output "db_user" {
  description = "Database username"
  value       = google_sql_user.user.name
}

output "db_name" {
  description = "Database name"
  value       = google_sql_database.database.name
}