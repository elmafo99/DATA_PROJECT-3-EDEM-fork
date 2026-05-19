
# This block points the Terraform state to the bucket created in GCP
terraform {
  backend "gcs" {
    bucket  = "terraform-state-data-project-2-491918"
    prefix  = "terraform/state/base"            
  }
}