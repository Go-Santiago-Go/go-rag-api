# infra/variables.tf
# Input variables for the stack. Declared here, referenced elsewhere as
# var.<name>. Defaults keep `terraform apply` a single command with no
# prompts, while still leaving each value overridable.
variable "aws_region" {
  description = "AWS region for all resources. Must be a region where Bedrock Titan v2 and the Claude model are available."
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository (owner/name) allowed to assume the CI role via OIDC. Case-sensitive: must match the repo exactly as GitHub stores it, since it is matched against the token's `sub` claim."
  type        = string
  default     = "Go-Santiago-Go/go-rag-api"
}
