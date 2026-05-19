# =============================================================================
# GENERIC GCS MODULE - Creates a single secure bucket
# =============================================================================

resource "google_storage_bucket" "bucket" {
    name                        = var.bucket_name
    location                    = var.region
    force_destroy               = !var.enable_deletion_protection
    uniform_bucket_level_access = true

    dynamic "cors" {
      for_each = var.enable_public_access ? [1] : []
      content {
        origin          = ["*"]
        method          = ["GET", "OPTIONS"]
        response_header = ["*"]
        max_age_seconds = 3600
      }
    }
}

resource "google_storage_bucket_iam_member" "public_read" {
  count  = var.enable_public_access ? 1 : 0
  bucket = google_storage_bucket.bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
