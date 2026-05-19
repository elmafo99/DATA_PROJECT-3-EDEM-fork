output "id" {
    value       = google_artifact_registry_repository.repo.id
    description = "The full ID of the repository"
}

output "name" {
    value       = google_artifact_registry_repository.repo.name
    description = "The name (path) of the repository"
}