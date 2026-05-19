output "bucket_name" {
  value       = google_storage_bucket.bucket.name
  description = "The name of the created bucket"
}
