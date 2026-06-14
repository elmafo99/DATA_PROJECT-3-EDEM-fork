output "endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "RDS hostname (no port) — use as DB_HOST"
  value       = aws_db_instance.this.address
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "db_user" {
  description = "Master username"
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the auto-generated master password"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group ID attached to the RDS instance"
  value       = aws_security_group.rds.id
}
