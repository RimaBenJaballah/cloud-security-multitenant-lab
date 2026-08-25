###############################################################################
# Application Load Balancer
###############################################################################

resource "aws_lb" "this" {
  name               = "sec-lab-alb-prod"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "sec-lab-alb-prod" }
}

###############################################################################
# Target Group
###############################################################################

resource "aws_lb_target_group" "this" {
  name        = "sec-lab-tg-prod"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "sec-lab-tg-prod" }
}

###############################################################################
# Listener — HTTP :80 → target group
###############################################################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

###############################################################################
# ECS Task Definition
###############################################################################

locals {
  container_image = var.container_image != "" ? var.container_image : "111111111111.dkr.ecr.eu-west-3.amazonaws.com/sec-lab-api:latest"
}

resource "aws_ecs_task_definition" "this" {
  family                   = "sec-lab-task-prod"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  task_role_arn      = var.task_role_arn
  execution_role_arn = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "sec-lab-api"
      image     = local.container_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AWS_REGION"
          value = "eu-west-3"
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = "eu-west-3"
        },
        {
          name  = "S3_BUCKET"
          value = "sec-lab-data-prod-xxxxxxxx"
        },
        {
          name  = "USE_LOCALSTACK"
          value = "false"
        },
        {
          name  = "DB_HOST"
          value = "sec-lab-db-prod.XXXXXXXXXXXX.eu-west-3.rds.amazonaws.com"
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = "tenantdb"
        }
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "arn:aws:secretsmanager:eu-west-3:111111111111:secret:rds/credentials-XXXXXX:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "arn:aws:secretsmanager:eu-west-3:111111111111:secret:rds/credentials-XXXXXX:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Name = "sec-lab-task-prod" }
}

###############################################################################
# ECS Service
###############################################################################

resource "aws_ecs_service" "this" {
  name            = "sec-lab-service-prod"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "sec-lab-api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "sec-lab-service-prod" }
}