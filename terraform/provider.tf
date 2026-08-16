terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Descomentar para usar S3 como backend (estado remoto)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "emergency-ops/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "emergency-ops"
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }
}
