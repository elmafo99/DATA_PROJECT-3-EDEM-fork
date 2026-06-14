variable "name_prefix" {
  description = "Prefix used for naming all resources (e.g. store-prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALBs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# API service (FastAPI)
# -----------------------------------------------------------------------------

variable "api_image" {
  description = "Container image URI for the API (ECR)"
  type        = string
}

variable "api_container_port" {
  description = "Port the API container listens on"
  type        = number
  default     = 8000
}

variable "api_env_vars" {
  description = "Plain environment variables for the API container"
  type        = map(string)
  default     = {}
}

variable "api_secrets" {
  description = "Map of env var name to Secrets Manager ARN (with optional ::key suffix for JSON secrets)"
  type        = map(string)
  default     = {}
}

variable "api_desired_count" {
  description = "Number of API tasks to run"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Frontend service (Nginx + React)
# -----------------------------------------------------------------------------

variable "frontend_image" {
  description = "Container image URI for the frontend (ECR)"
  type        = string
}

variable "frontend_container_port" {
  description = "Port the frontend container listens on"
  type        = number
  default     = 80
}

variable "frontend_desired_count" {
  description = "Number of frontend tasks to run"
  type        = number
  default     = 1
}

variable "deploy_frontend" {
  description = "Whether to create the frontend ECS service. Set false on the first apply pass (before the frontend image, which embeds the API URL, has been built/pushed)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# DB init job (one-off task — runs 01-schema.sql)
# -----------------------------------------------------------------------------

variable "db_init_image" {
  description = "Container image URI for the db-init one-off task (ECR)"
  type        = string
}

variable "db_init_env_vars" {
  description = "Plain environment variables for the db-init container"
  type        = map(string)
  default     = {}
}

variable "db_init_secrets" {
  description = "Map of env var name to Secrets Manager ARN for the db-init container"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Migration subscription task (one-off, run manually via run-task — sets up
# logical replication from GCP Cloud SQL into RDS)
# -----------------------------------------------------------------------------

variable "migration_sub_image" {
  description = "Container image URI for the migration-sub one-off task (ECR, :subscription tag)"
  type        = string
  default     = ""
}

variable "migration_sub_env_vars" {
  description = "Plain environment variables for the migration-sub container"
  type        = map(string)
  default     = {}
}

variable "migration_secrets" {
  description = "Map of env var name to Secrets Manager ARN used by the migration-sub task (in addition to db_init_secrets), granted to the shared ECS execution role"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Shared
# -----------------------------------------------------------------------------

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory in MB"
  type        = string
  default     = "512"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 14
}

variable "labels" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
