variable "app_name" {
  description = "Application name, used as a prefix in resource names"
  type        = string
  default     = "store"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "aws_account_id" {
  description = "AWS account ID — terraform refuses to apply against any other account"
  type        = string
}

variable "deploy_frontend" {
  description = "Set false on the first apply pass — ECR repos must exist and the API must be reachable before the frontend image (which embeds VITE_API_URL) can be built."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# GCP source (read-only, for terraform_remote_state)
# -----------------------------------------------------------------------------

variable "gcp_project_id" {
  description = "GCP project ID hosting the source Cloud SQL instance"
  type        = string
}

variable "gcp_region" {
  description = "GCP region of the source environment"
  type        = string
  default     = "europe-west1"
}

variable "gcp_tfstate_bucket" {
  description = "GCS bucket holding the GCP Terraform state"
  type        = string
  default     = "serel"
}

