
# This block points the Terraform state to the bucket created in GCP
terraform {
  backend "gcs" {
    bucket  = "bucker_exa"
    prefix  = "terraform/state/base"            
  }
}