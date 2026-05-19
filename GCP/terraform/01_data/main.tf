
# This block points the Terraform state to the bucket created in GCP
terraform {
  backend "gcs" {
    bucket  = "terraform-state-data-project-2-491918"
    prefix  = "terraform/state/data"            
  }
}

# This block points the Terraform base state in the bucket
data "terraform_remote_state" "base" {
  backend = "gcs"
  
  config = {
    bucket = "terraform-state-data-project-2-491918" # El nombre de tu bucket de estados
    prefix = "terraform/state/base"
  }
}