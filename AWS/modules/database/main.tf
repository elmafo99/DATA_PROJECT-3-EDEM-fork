# =============================================================================
# DATABASE MODULE — RDS PostgreSQL (logical replication enabled for PG->PG migration)
# =============================================================================

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.labels, { Name = "${var.name_prefix}-db-subnets" })
}

resource "aws_security_group" "rds" {
  name   = "${var.name_prefix}-rds-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "Postgres from within the VPC (ECS tasks)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.labels, { Name = "${var.name_prefix}-rds-sg" })
}

# Required for logical replication subscription (CDC from Cloud SQL during migration)
resource "aws_db_parameter_group" "pg15" {
  name   = "${var.name_prefix}-pg15-logical"
  family = "postgres15"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(var.labels, { Name = "${var.name_prefix}-pg15-logical" })
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_user

  manage_master_user_password = true

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.pg15.name

  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-db-final"

  tags = merge(var.labels, { Name = "${var.name_prefix}-db" })
}
