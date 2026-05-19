variable "region" {
  description = "GCP region where the generic bucket will be created"
  type        = string
}

# Injected as a variable in the module call.
variable "bucket_name" {
  description = "The globally unique name of the bucket"
  type        = string
}

# Injected as a variable in the module call.
variable "enable_deletion_protection" {
  description = "If true, prevents accidental deletion of the bucket"
  type        = bool
}

variable "enable_public_access" {
  description = "Si true, configura CORS abierto (GET/OPTIONS) y acceso de lectura público (allUsers → roles/storage.objectViewer). Usar solo para buckets que sirven estáticos al navegador."
  type        = bool
  default     = false
}