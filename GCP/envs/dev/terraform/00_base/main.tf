
# This block points the Terraform state to the bucket created in GCP
terraform {
  backend "gcs" {
    bucket  = "bucket-terraform-state-dp3"
    prefix  = "terraform/state/base"            
  }
}