module "app_sa" {
  source       = "../../../../modules/service_account"
  account_id   = "${var.app_name}-sa-${var.environment}"
  display_name = "Tienda de Ropa ${upper(var.environment)} - App"
  description  = "Single service account for all tienda-de-ropa services in ${var.environment}"
}

locals {
  sa_roles = [
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/artifactregistry.reader",
    "roles/storage.objectViewer",
  ]
}

resource "google_project_iam_member" "app_sa_roles" {
  for_each = toset(local.sa_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${module.app_sa.email}"
}
