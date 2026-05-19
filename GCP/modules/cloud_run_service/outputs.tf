output "service_url" {
  description = "URL assigned to the Cloud Run service"
  value       = google_cloud_run_v2_service.default.uri
}

output "service_id" {
  description = "Unique identifier of the service"
  value       = google_cloud_run_v2_service.default.id
}

output "service_account_used" {
  description = "Service Account currently running the service"
  value       = google_cloud_run_v2_service.default.template[0].service_account
}