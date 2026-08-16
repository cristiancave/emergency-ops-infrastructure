terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    bucket = "terraform-state-emergency-ops-gcp-476583311075"
    prefix = "emergency-ops-gcp"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
