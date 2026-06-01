
# This block points the Terraform state to the bucket created in GCP
terraform {
  backend "gcs" {
    bucket  = "serel"
    prefix  = "terraform/state/base"            
  }
}