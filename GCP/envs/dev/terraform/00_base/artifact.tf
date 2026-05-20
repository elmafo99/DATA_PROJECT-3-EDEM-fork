module "artifact_registry" {
    source        = "../../../../modules/artifact_registry"
    repository_id = "${var.app_name}-${var.environment}"
    region        = var.region
    description   = "Docker repository for the store pipeline images in ${var.environment}"
}