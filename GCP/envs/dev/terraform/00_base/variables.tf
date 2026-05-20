variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region where resources will be deployed"
  type        = string
  default     = "europe-west1"
}

variable "app_name" {
  description = "Application name, used as a prefix in resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}
