variable "account_id" {
  description = "Technical unique ID for the Service Account (e.g. 'sa-ingestion-dev'). Only lowercase letters, numbers and hyphens allowed (max. 30 characters)."
  type = string
}

variable "display_name" {
  description = "Friendly display name shown in the GCP web console (e.g. 'SA for Air Quality Data Ingestion')."
  type = string
}

variable "description" {
  description = "Description of the service account's purpose"
  type = string
}