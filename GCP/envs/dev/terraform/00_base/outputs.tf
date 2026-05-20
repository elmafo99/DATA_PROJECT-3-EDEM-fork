output "app_sa_email" {
  description = "Email of the shared service account used by all app services"
  value       = module.app_sa.email
}
