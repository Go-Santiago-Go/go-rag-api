# infra/bootstrap/versions.tf
# The PERSISTENT stack. It holds only free, long-lived resources (the ECR
# repository and the GitHub OIDC CI role) that must outlive the nightly
# `terraform destroy` of the billable app stack in infra/. Apply this once and
# leave it up, so CI can push images at any time and the app stack can look the
# repository up by name.
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "go-rag-api"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
