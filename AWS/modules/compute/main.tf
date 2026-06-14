# =============================================================================
# COMPUTE MODULE — ECS Fargate (API + Frontend) behind ALBs, plus a one-off
# db-init task. Mirrors the GCP setup: 2 public services + 1 init job.
# =============================================================================

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  tags = merge(var.labels, { Name = "${var.name_prefix}-cluster" })
}

# -----------------------------------------------------------------------------
# IAM — execution role (pull image, write logs, read secrets) and task role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = var.labels
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Execution role needs to read the RDS master password secret to inject it as an env var.
# valueFrom strings carry a ":json-key::" suffix for ECS; IAM resource ARNs must not —
# strip it, and allow the trailing "-xxxxxx" AWS appends to managed secret ARNs.
data "aws_iam_policy_document" "secrets_read" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = distinct([
      for v in concat(values(var.api_secrets), values(var.db_init_secrets), values(var.migration_secrets)) :
      "${split(":", v)[0]}:${split(":", v)[1]}:${split(":", v)[2]}:${split(":", v)[3]}:${split(":", v)[4]}:${split(":", v)[5]}:${split(":", v)[6]}*"
    ])
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${var.name_prefix}-ecs-execution-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = var.labels
}

# -----------------------------------------------------------------------------
# Logs
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name_prefix}-api"
  retention_in_days = var.log_retention_days

  tags = var.labels
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.name_prefix}-frontend"
  retention_in_days = var.log_retention_days

  tags = var.labels
}

resource "aws_cloudwatch_log_group" "db_init" {
  name              = "/ecs/${var.name_prefix}-db-init"
  retention_in_days = var.log_retention_days

  tags = var.labels
}

resource "aws_cloudwatch_log_group" "migration_sub" {
  name              = "/ecs/${var.name_prefix}-migration-sub"
  retention_in_days = var.log_retention_days

  tags = var.labels
}

# -----------------------------------------------------------------------------
# Security groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name   = "${var.name_prefix}-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.labels, { Name = "${var.name_prefix}-alb-sg" })
}

resource "aws_security_group" "ecs_tasks" {
  name   = "${var.name_prefix}-ecs-tasks-sg"
  vpc_id = var.vpc_id

  ingress {
    description     = "API from ALB"
    from_port       = var.api_container_port
    to_port         = var.api_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Frontend from ALB"
    from_port       = var.frontend_container_port
    to_port         = var.frontend_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.labels, { Name = "${var.name_prefix}-ecs-tasks-sg" })
}

# -----------------------------------------------------------------------------
# API — ALB + target group + ECS service
# -----------------------------------------------------------------------------

resource "aws_lb" "api" {
  name               = "${var.name_prefix}-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.labels, { Name = "${var.name_prefix}-api-alb" })
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name_prefix}-api-tg"
  port        = var.api_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/ping"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }

  tags = var.labels
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = var.api_image
      essential = true
      portMappings = [
        { containerPort = var.api_container_port, protocol = "tcp" }
      ]
      environment = [for k, v in var.api_env_vars : { name = k, value = v }]
      secrets     = [for k, v in var.api_secrets : { name = k, valueFrom = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "api"
        }
      }
    }
  ])

  tags = var.labels
}

resource "aws_ecs_service" "api" {
  name            = "${var.name_prefix}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.api_container_port
  }

  depends_on = [aws_lb_listener.api]

  tags = var.labels
}

# -----------------------------------------------------------------------------
# Frontend — ALB + target group + ECS service
# -----------------------------------------------------------------------------

resource "aws_lb" "frontend" {
  count              = var.deploy_frontend ? 1 : 0
  name               = "${var.name_prefix}-frontend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.labels, { Name = "${var.name_prefix}-frontend-alb" })
}

resource "aws_lb_target_group" "frontend" {
  count       = var.deploy_frontend ? 1 : 0
  name        = "${var.name_prefix}-frontend-tg"
  port        = var.frontend_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }

  tags = var.labels
}

resource "aws_lb_listener" "frontend" {
  count             = var.deploy_frontend ? 1 : 0
  load_balancer_arn = aws_lb.frontend[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend[0].arn
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.name_prefix}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = var.frontend_image
      essential = true
      portMappings = [
        { containerPort = var.frontend_container_port, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])

  tags = var.labels
}

resource "aws_ecs_service" "frontend" {
  count           = var.deploy_frontend ? 1 : 0
  name            = "${var.name_prefix}-frontend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend[0].arn
    container_name   = "frontend"
    container_port   = var.frontend_container_port
  }

  depends_on = [aws_lb_listener.frontend]

  tags = var.labels
}

# -----------------------------------------------------------------------------
# DB init — one-off Fargate task definition (run manually via run-task,
# mirrors the GCP Cloud Run Job that applies 01-schema.sql)
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "db_init" {
  family                   = "${var.name_prefix}-db-init"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "db-init"
      image       = var.db_init_image
      essential   = true
      environment = [for k, v in var.db_init_env_vars : { name = k, value = v }]
      secrets     = [for k, v in var.db_init_secrets : { name = k, valueFrom = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.db_init.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "db-init"
        }
      }
    }
  ])

  tags = var.labels
}

# -----------------------------------------------------------------------------
# Migration subscription — one-off Fargate task definition (run manually via
# run-task), creates/manages the logical replication subscription from GCP
# Cloud SQL into RDS. Reuses the db-init image (":subscription" tag).
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "migration_sub" {
  family                   = "${var.name_prefix}-migration-sub"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "migration-sub"
      image       = var.migration_sub_image
      essential   = true
      environment = [for k, v in var.migration_sub_env_vars : { name = k, value = v }]
      secrets     = [for k, v in merge(var.db_init_secrets, var.migration_secrets) : { name = k, valueFrom = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.migration_sub.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "migration-sub"
        }
      }
    }
  ])

  tags = var.labels
}

data "aws_region" "current" {}
