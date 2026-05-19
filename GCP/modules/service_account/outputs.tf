output "email" {
  value       = google_service_account.service_account.email
  description = "The generated email address of the Service Account. Required for assigning permissions in IAM blocks."
}

output "id" {
  value       = google_service_account.service_account.id
  description = "The fully-qualified identifier of the Service Account."
}