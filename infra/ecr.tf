# infra/ecr.tf
# The private container registry for the service image. CI builds the Docker
# image and pushes it here; ECS Express Mode pulls it from here to run.
resource "aws_ecr_repository" "app" {
  name = "go-rag-api"

  # MUTABLE lets a tag (e.g. :latest) be overwritten by a newer push. Convenient
  # for a demo. IMMUTABLE would forbid overwriting a tag (safer for production,
  # since a deployed tag can never silently change) at the cost of some friction.
  image_tag_mutability = "MUTABLE"

  # Scan each image for known CVEs on push. Free, and the Well-Architected
  # default: surfaces a vulnerable base image without running anything.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Let `terraform destroy` delete the repo even if images remain inside.
  # Same throwaway-demo reasoning as the S3 bucket's force_destroy.
  force_delete = true

  tags = { Name = "go-rag-api" }
}
