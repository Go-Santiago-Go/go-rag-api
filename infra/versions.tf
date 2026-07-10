# infra/versions.tf
# Pins the Terraform CLI and the AWS provider, and configures that provider.
# Version pinning makes `apply` reproducible: a newer provider can't silently
# introduce breaking changes on a future `init`. (Credentials are NOT here;
# the provider reads them from the same chain as the AWS CLI.)
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # allow any 6.x, block the 7.0 breaking-change jump
    }
  }
}

# The AWS provider: which region to build in, plus tags stamped on every
# taggable resource so the whole stack is easy to find and clean up.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "go-rag-api"
      ManagedBy = "terraform"
    }
  }
}
