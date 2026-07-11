# infra/ecs.tf
# The compute tier: an ECS Express Mode service. Express Mode provisions the
# Fargate service, an internet-facing load balancer, TLS, autoscaling, and the
# security-group wiring between the LB and the tasks, from just a container
# image plus three roles. We supply our own VPC subnets so the task can reach
# the private RDS instance.

# The container image lives in the persistent bootstrap stack's ECR repository
# (infra/bootstrap), which is managed in a separate Terraform state. Look it up
# by name rather than referencing the resource directly; the bootstrap stack
# must be applied first.
data "aws_ecr_repository" "app" {
  name = "go-rag-api"
}

# ---------------------------------------------------------------------------
# Execution role: WHO pulls the image and starts the container
# ---------------------------------------------------------------------------
# ECS (not the app) uses this role to pull from ECR, write logs, and fetch the
# secrets injected into the container. It reuses the ecs-tasks trust policy from
# iam.tf (same ecs-tasks.amazonaws.com principal as the task role).
resource "aws_iam_role" "execution" {
  name               = "go-rag-api-execution"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags               = { Name = "go-rag-api-execution" }
}

# The AWS-managed baseline: pull from ECR + write to CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additionally allow reading ONLY the RDS-managed master-user secret, so ECS can
# inject the DB password (PGPASSWORD) into the container at launch. Scoped to the
# one secret ARN; the password never enters the image or Terraform state.
data "aws_iam_policy_document" "execution_secret" {
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.vectors.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "execution_secret" {
  name   = "go-rag-api-execution-secret"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secret.json
}

# ---------------------------------------------------------------------------
# Infrastructure role: what Express Mode assumes to build the load balancer
# ---------------------------------------------------------------------------
# Trusted by the ECS service principal (ecs.amazonaws.com, not ecs-tasks), this
# role lets Express Mode create and manage the ALB, target groups, security
# groups, and scaling on our behalf.
data "aws_iam_policy_document" "infrastructure_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "infrastructure" {
  name               = "go-rag-api-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.infrastructure_assume.json
  tags               = { Name = "go-rag-api-infrastructure" }
}

resource "aws_iam_role_policy_attachment" "infrastructure_managed" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

# ---------------------------------------------------------------------------
# The Express Mode service
# ---------------------------------------------------------------------------
resource "aws_ecs_express_gateway_service" "app" {
  service_name = "go-rag-api"

  # The three identities: execution (pull/logs/secrets), infrastructure (build
  # the LB), and task (the app's own Bedrock + S3 permissions from iam.tf).
  execution_role_arn      = aws_iam_role.execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  task_role_arn           = aws_iam_role.task.arn

  # Smallest sensible Fargate size: 0.5 vCPU / 1 GB.
  cpu    = "512"
  memory = "1024"

  # The ALB health check hits this path; our service serves it with no DB or
  # Bedrock dependency, so it reports healthy as soon as the process is up.
  health_check_path = "/health"

  # Express Mode uses ONE subnet set for both the load balancer and the tasks:
  # public subnets -> internet-facing ALB + public task IPs; private subnets ->
  # internal ALB. We need a public URL, so we use the public subnets. The tasks
  # get public IPs but remain unreachable from the internet except through the
  # ALB, because the app security group has no inbound rule of its own (Express
  # adds only the LB->task rule). Tasks still reach RDS via the app SG (the DB SG
  # allows it) and reach Bedrock/ECR directly via the internet gateway.
  #
  # Note: the first Express service in a VPC fixes that VPC's LB subnet
  # association, so changing this list replaces the service rather than updating
  # it in place.
  network_configuration {
    subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups = [aws_security_group.app.id]
  }

  primary_container {
    image          = "${data.aws_ecr_repository.app.repository_url}:latest"
    container_port = 8080

    # Non-secret DB connection parts. pgx assembles the DSN from these plus the
    # injected PGPASSWORD (see cmd/server/main.go).
    environment {
      name  = "PGHOST"
      value = aws_db_instance.vectors.address
    }
    environment {
      name  = "PGUSER"
      value = aws_db_instance.vectors.username
    }
    environment {
      name  = "PGDATABASE"
      value = aws_db_instance.vectors.db_name
    }
    environment {
      name  = "PGSSLMODE"
      value = "require" # RDS requires TLS; do not disable in the cloud
    }

    # The password, pulled from the RDS-managed secret's `password` key by ECS at
    # launch. The `:password::` suffix selects that JSON key from the secret.
    secret {
      name       = "PGPASSWORD"
      value_from = "${aws_db_instance.vectors.master_user_secret[0].secret_arn}:password::"
    }
  }

  # Block `apply` until the service is healthy, so a green apply means a live URL
  # (and a broken deploy surfaces here rather than silently).
  wait_for_steady_state = true

  tags = { Name = "go-rag-api" }
}

# ---------------------------------------------------------------------------
# Output: the public URL
# ---------------------------------------------------------------------------
# Express Mode auto-generates the endpoint; surface it so it lands in the README.
output "service_url" {
  description = "Public URL of the ECS Express Mode service."
  value       = aws_ecs_express_gateway_service.app.ingress_paths[*].endpoint
}
