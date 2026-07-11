# infra/bootstrap/ecr.tf
# The private container registry for the service image. CI builds the Docker
# image and pushes it here; ECS Express Mode pulls it from here to run. Lives in
# the persistent stack so images survive the app stack's nightly destroy.
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
  force_delete = true

  tags = { Name = "go-rag-api" }
}
