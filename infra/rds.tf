# infra/rds.tf
# The data tier: a private RDS Postgres instance (the cloud vector store) plus
# the two things it needs to live in our VPC safely, a subnet group and a
# security group. Nothing here is reachable from the internet; the only client
# that can connect is a resource inside the VPC holding the app security group.

# ---------------------------------------------------------------------------
# Security groups (identities that chain by reference, not by IP)
# ---------------------------------------------------------------------------

# App security group: the identity the ECS task carries. It deliberately has no
# inbound rule of its own; ECS Express Mode adds the "allow from the load
# balancer on the container port" rule itself when it provisions the ALB, so the
# tasks stay unreachable from the internet even though they run in public
# subnets. The DB security group below references this SG: the DB grants access
# to "whoever holds this SG," not to an IP range that can drift.
resource "aws_security_group" "app" {
  name        = "go-rag-api-app"
  description = "ECS task: outbound to Bedrock/RDS; inbound from ALB (added in Phase 8)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "go-rag-api-app" }
}

# The app initiates connections outward (to RDS, and to Bedrock/ECR via the NAT
# gateway), so it needs egress. Terraform-managed SGs have NO egress by default,
# you must declare it explicitly or all outbound is denied.
resource "aws_vpc_security_group_egress_rule" "app_all_out" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # all protocols/ports
}

# DB security group: the host-layer firewall on the database.
resource "aws_security_group" "db" {
  name        = "go-rag-api-db"
  description = "Postgres: inbound 5432 only from the app security group"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "go-rag-api-db" }
}

# The only way in: port 5432 from the app SG. referenced_security_group_id (not
# a CIDR) is what makes this "allow the app, wherever it happens to run." No
# egress rule is needed because security groups are stateful: the response to an
# allowed inbound connection is permitted automatically, and a database does not
# initiate outbound connections of its own.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------------------
# DB subnet group: which subnets RDS may place the instance in
# ---------------------------------------------------------------------------
# RDS is managed and may relocate the instance (failover, maintenance, restore),
# so you hand it a GROUP of subnets across AZs rather than one subnet. It
# requires >= 2 AZs even for a single-AZ instance, which is why the data tier is
# a pair. Both are private (no internet route), so the DB lands nowhere public.
resource "aws_db_subnet_group" "main" {
  name       = "go-rag-api-data"
  subnet_ids = [aws_subnet.data_a.id, aws_subnet.data_b.id]
  tags       = { Name = "go-rag-api-data" }
}

# ---------------------------------------------------------------------------
# The RDS Postgres instance
# ---------------------------------------------------------------------------
resource "aws_db_instance" "vectors" {
  identifier     = "go-rag-api-vectors"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro" # smallest ARM Graviton; free-tier eligible

  allocated_storage = 20    # GB; 20 is the gp3 minimum, plenty for a demo
  storage_type      = "gp3" # general-purpose SSD
  storage_encrypted = true  # encryption at rest is free; no reason not to

  db_name  = "ragdb"   # the initial database created inside the instance
  username = "raguser" # master user

  # Let RDS generate the master password and store it in Secrets Manager, so the
  # secret never lives in Terraform state or a .tfvars file. In Phase 8 ECS
  # injects it into the container as PGPASSWORD from this secret at launch (see
  # ecs.tf); the app assembles its connection from the PG* env vars.
  manage_master_user_password = true

  # Placement: private subnet group + DB security group = no public path in.
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false # single-AZ: cheaper, and a demo we destroy nightly

  # Teardown hygiene: skip the final snapshot so `terraform destroy` completes
  # cleanly and leaves nothing chargeable. Correct for a throwaway DB ONLY.
  skip_final_snapshot = true

  tags = { Name = "go-rag-api-vectors" }

  # pgvector is a supported RDS extension but is NOT enabled here; enabling it is
  # runtime SQL (`CREATE EXTENSION vector`), run with the schema migration at the
  # Go service's startup from inside the VPC (Phase 8). Terraform provisions the
  # instance; the app owns its schema.
}
