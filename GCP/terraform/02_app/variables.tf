variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region where resources will be deployed"
  type        = string
  default     = "europe-west1"
}
