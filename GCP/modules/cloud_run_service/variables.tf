variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cloud_run_config" {
  description = "Cloud Run service configuration"
  type = object({
    name               = string
    location           = string
    image              = string
    container_port     = optional(number, 8080)
    max_instance_count = optional(number, 10)
  })
}

variable "service_account_email" {
  description = "Email of the Service Account that will run the service"
  type        = string
}

variable "allow_public_access" {
  description = "If true, allows unauthenticated invocations (IAM binding for allUsers)"
  type        = bool
  default     = false
}

variable "env_vars" {
  description = "Map of environment variables to inject into the container"
  type        = map(string)
  default     = {}
}