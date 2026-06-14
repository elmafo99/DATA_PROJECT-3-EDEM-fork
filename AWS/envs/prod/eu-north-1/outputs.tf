output "ecr_repository_urls" {
  description = "Map of image name to ECR repository URL — push images here before first apply"
  value       = module.ecr.repository_urls
}

output "nat_eip" {
  description = "Allowlist this IP on Cloud SQL authorized_networks (Phase 2)"
  value       = module.network.nat_eip
}

output "rds_endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = module.database.endpoint
}

output "rds_address" {
  description = "RDS hostname"
  value       = module.database.address
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master password"
  value       = module.database.master_user_secret_arn
}

output "api_url" {
  description = "Public URL of the API (ALB)"
  value       = module.compute.api_url
}

output "frontend_url" {
  description = "Public URL of the frontend (ALB)"
  value       = module.compute.frontend_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.compute.cluster_name
}

output "db_init_task_definition_arn" {
  description = "Task definition ARN for the one-off db-init task — run once via run-task"
  value       = module.compute.db_init_task_definition_arn
}

output "db_init_subnet_ids" {
  description = "Private subnet IDs to pass to 'aws ecs run-task' for the db-init task"
  value       = module.compute.private_subnet_ids
}

output "db_init_security_group_id" {
  description = "Security group ID to pass to 'aws ecs run-task' for the db-init task"
  value       = module.compute.ecs_tasks_security_group_id
}

output "gcp_db_public_ip" {
  description = "Source Cloud SQL public IP (for the logical replication subscription, Phase 3)"
  value       = local.gcp_db_public_ip
}
