output "api_service_url" {
  description = "Public URL of the API Cloud Run service"
  value       = module.api_service.service_url
}

output "frontend_service_url" {
  description = "Public URL of the Frontend Cloud Run service"
  value       = module.frontend_service.service_url
}
