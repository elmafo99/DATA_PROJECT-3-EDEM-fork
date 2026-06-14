variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region where all resources will be deployed"
  type        = string
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance"
  type        = string
}

variable "db_name" {
  description = "Name of the Cloud SQL database"
  type        = string
}

variable "db_user" {
  description = "Cloud SQL database user"
  type        = string
}

variable "db_password" {
  description = "Cloud SQL database password"
  type        = string
  sensitive   = true # Prevents the value from being printed in the Terraform console
}

variable "machine_tier" {
  description = "Machine tier (e.g. db-f1-micro for dev, db-custom-2-7680 for prod)"
  type        = string
  default     = "db-f1-micro"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 10
}

variable "disk_type" {
  description = "Disk type: PD_SSD (fast/prod) or PD_HDD (cheap/dev)"
  type        = string
  default     = "PD_HDD"
}

variable "enable_deletion_protection" {
  description = "Prevents accidental deletion of the Cloud SQL instance"
  type        = bool
}

variable "authorized_networks" {
  description = "External CIDR blocks allowed to connect (e.g. AWS NAT Gateway EIP during migration)"
  type = list(object({
    name       = string
    cidr_block = string
  }))
  default = []
}