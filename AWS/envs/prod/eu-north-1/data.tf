# Reads outputs from the GCP 01_data layer (Cloud SQL connection details)
# so this stack stays connected to the source environment without merging
# the two Terraform states.
data "terraform_remote_state" "gcp_data" {
  backend = "gcs"

  config = {
    bucket = var.gcp_tfstate_bucket
    prefix = "terraform/state/data"
  }
}

locals {
  gcp_db_public_ip          = data.terraform_remote_state.gcp_data.outputs.db_public_ip
  gcp_db_user               = data.terraform_remote_state.gcp_data.outputs.db_user
  gcp_db_name               = data.terraform_remote_state.gcp_data.outputs.db_name
  gcp_db_password_secret_id = data.terraform_remote_state.gcp_data.outputs.db_password_secret_id
}
