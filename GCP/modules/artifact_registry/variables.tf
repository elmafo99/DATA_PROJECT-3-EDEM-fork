variable "repository_id" {
    description = "The repository ID"
    type        = string
}

variable "region" {
    description = "The region where the repository will be hosted"
    type        = string
}

variable "description" {
    description = "Repository description"
    type        = string
    default     = "Docker image repository"
}