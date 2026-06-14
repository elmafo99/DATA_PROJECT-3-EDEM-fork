variable "name_prefix" {
  description = "Prefix used for naming all resources (e.g. store-prod)"
  type        = string
}

variable "repository_names" {
  description = "Image names to create ECR repos for (e.g. [\"api\", \"frontend\", \"db-init\"])"
  type        = list(string)
}

variable "labels" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
