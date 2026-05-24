variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "job_name" {
  description = "Name of the Cloud Run job"
  type        = string
}

variable "region" {
  description = "GCP region where the job will run"
  type        = string
}

variable "service_account_email" {
  description = "Email of the Service Account that will run the job"
  type        = string
}

variable "image_url" {
  description = "Full Artifact Registry URL of the container image"
  type        = string
}

variable "env_vars" {
  description = "Map of plain environment variables"
  type        = map(string)
  default     = {}
}

variable "secret_env_vars" {
  description = "Map of env var name to Secret Manager secret ID"
  type        = map(string)
  default     = {}
}

variable "cloud_sql_instances" {
  description = "List of Cloud SQL instance connection names to mount as Unix sockets"
  type        = list(string)
  default     = []
}
