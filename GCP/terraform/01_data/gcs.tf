
module "bucket_cartography" {
    source                     = "../../../../modules/gcs"
    bucket_name                = "${var.project_id}-${var.app_name}-cartography-${var.environment}"
    region                     = var.region
    enable_deletion_protection = false # Dev environment — deletion is allowed
    enable_public_access       = false  # Sirve estáticos (GeoJSON/JSON) al frontend vía navegador
}

# Upload the valencia_barrios.geojson file to the bucket
resource "google_storage_bucket_object" "cartography_file" {
  name   = "valencia_barrios.geojson"
  
  # Using ${path.module} forces Terraform to anchor the path to the current folder
  source = "${path.module}/../../../../src/data/valencia_barrios.geojson" 
  
  bucket = module.bucket_cartography.bucket_name
}

# Upload the adjacency.json file to the bucket
resource "google_storage_bucket_object" "adjacency_file" {
  name   = "adjacency.json"
  
  # Using ${path.module} forces Terraform to anchor the path to the current folder
  source = "${path.module}/../../../../src/data/adjacency.json" 
  
  bucket = module.bucket_cartography.bucket_name
}

# Upload the game_config.json file to the bucket
resource "google_storage_bucket_object" "game_config_file" {
  name   = "game_config.json"
  
  # Using ${path.module} forces Terraform to anchor the path to the current folder
  source = "${path.module}/../../../../src/data/game_config.json" 
  
  bucket = module.bucket_cartography.bucket_name
}

# Upload the players.json file to the bucket
resource "google_storage_bucket_object" "players_file" {
  name   = "players.json"
  
  # Using ${path.module} forces Terraform to anchor the path to the current folder
  source = "${path.module}/../../../../src/data/players.json" 
  
  bucket = module.bucket_cartography.bucket_name
}

# Upload the initial_gameState.json file to the bucket
resource "google_storage_bucket_object" "initial_gameState" {
  name   = "initial_gameState.json"
  
  # Using ${path.module} forces Terraform to anchor the path to the current folder
  source = "${path.module}/../../../../src/data/initial_gameState.json" 
  
  bucket = module.bucket_cartography.bucket_name
}

# Temporary Bucket (Dataflow)
module "bucket_temp" {
    source                     = "../../../../modules/gcs"
    bucket_name                = "${var.project_id}-${var.app_name}-dataflow-temp-${var.environment}"
    region                     = var.region
    enable_deletion_protection = false # Dev environment — deletion is allowed
}

