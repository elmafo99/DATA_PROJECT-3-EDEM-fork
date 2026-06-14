terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- TARGET ---
provider "aws" {
  region              = "eu-north-1"
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      project     = var.app_name
      managed_by  = "terraform"
      migration   = "gcp-to-aws"
      environment = var.environment
    }
  }
}

# --- SOURCE (read-only access to GCP state outputs) ---
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
