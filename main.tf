terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Remote state backend — uncomment after first apply, then run: terraform init -migrate-state
  # backend "s3" {
  #   bucket         = "vpn-tfstate-YOUR_ACCOUNT_ID"
  #   key            = "vpn/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "vpn-terraform-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}
