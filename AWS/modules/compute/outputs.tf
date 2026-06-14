output "api_url" {
  description = "Public DNS name of the API ALB"
  value       = "http://${aws_lb.api.dns_name}"
}

output "frontend_url" {
  description = "Public DNS name of the frontend ALB (null if deploy_frontend=false)"
  value       = var.deploy_frontend ? "http://${aws_lb.frontend[0].dns_name}" : null
}

output "api_alb_dns_name" {
  description = "Raw DNS name of the API ALB (for Route53 alias records)"
  value       = aws_lb.api.dns_name
}

output "api_alb_zone_id" {
  description = "Hosted zone ID of the API ALB (for Route53 alias records)"
  value       = aws_lb.api.zone_id
}

output "frontend_alb_dns_name" {
  description = "Raw DNS name of the frontend ALB (for Route53 alias records; null if deploy_frontend=false)"
  value       = var.deploy_frontend ? aws_lb.frontend[0].dns_name : null
}

output "frontend_alb_zone_id" {
  description = "Hosted zone ID of the frontend ALB (for Route53 alias records; null if deploy_frontend=false)"
  value       = var.deploy_frontend ? aws_lb.frontend[0].zone_id : null
}

output "cluster_name" {
  description = "ECS cluster name (for running the db-init task)"
  value       = aws_ecs_cluster.this.name
}

output "db_init_task_definition_arn" {
  description = "Task definition ARN for the one-off db-init task"
  value       = aws_ecs_task_definition.db_init.arn
}

output "private_subnet_ids" {
  description = "Private subnet IDs (needed to run the db-init task via run-task)"
  value       = var.private_subnet_ids
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks (needed to run the db-init task via run-task)"
  value       = aws_security_group.ecs_tasks.id
}
