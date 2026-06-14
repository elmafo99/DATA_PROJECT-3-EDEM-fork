variable "name_prefix" {
  description = "Prefix used for naming all resources (e.g. store-prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the RDS instance will be placed"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — only this range can reach Postgres on 5432"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "db_name" {
  description = "Name of the initial database"
  type        = string
}

variable "db_user" {
  description = "Master username"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t4g.micro for dev/migration)"
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version — must match Cloud SQL source for logical replication"
  type        = string
  default     = "15.18"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 10
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "labels" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
