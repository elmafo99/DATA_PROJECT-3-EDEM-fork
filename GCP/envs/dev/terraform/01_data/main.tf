
# This block points the Terraform state to the bucket created in GCP
terraform {
  backend "gcs" {
    bucket  = "bucker_exa"
    prefix  = "terraform/state/data"            
  }
}

# This block points the Terraform base state in the bucket
data "terraform_remote_state" "base" {
  backend = "gcs"
  
  config = {
    bucket = "bucker_exa" # El nombre de tu bucket de estados
    prefix = "terraform/state/base"
  }
}