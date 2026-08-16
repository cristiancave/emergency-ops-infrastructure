# ==============================================================
# Config del OTel Collector, en SSM Parameter Store.
# La distribución ADOT (AWS Distro for OpenTelemetry) sabe leer su
# config directamente desde SSM con --config=ssm:<param-name>, así
# no hace falta hornear una imagen custom ni otro pipeline de build.
# ==============================================================
resource "aws_ssm_parameter" "otel_collector_config" {
  name = "/${var.project_name}/otel-collector-config"
  type = "String"

  value = yamlencode({
    receivers = {
      otlp = {
        protocols = {
          grpc = { endpoint = "0.0.0.0:4317" }
          http = { endpoint = "0.0.0.0:4318" }
        }
      }
    }

    processors = {
      memory_limiter = {
        check_interval  = "1s"
        limit_mib       = 400
        spike_limit_mib = 100
      }
      resource = {
        attributes = [
          {
            key    = "deployment.environment"
            value  = var.environment
            action = "upsert"
          }
        ]
      }
      batch = {
        timeout         = "5s"
        send_batch_size = 512
      }
    }

    exporters = {
      awsxray = {
        region = var.aws_region
      }
      prometheus = {
        endpoint = "0.0.0.0:8889"
      }
    }

    extensions = {
      health_check = { endpoint = "0.0.0.0:13133" }
    }

    service = {
      extensions = ["health_check"]
      pipelines = {
        traces = {
          receivers  = ["otlp"]
          processors = ["memory_limiter", "resource", "batch"]
          exporters  = ["awsxray"]
        }
        metrics = {
          receivers  = ["otlp"]
          processors = ["memory_limiter", "resource", "batch"]
          exporters  = ["prometheus"]
        }
      }
      telemetry = {
        metrics = {
          level = "detailed"
        }
      }
    }
  })

  tags = {
    Name = "${var.project_name}-otel-collector-config"
  }
}

# ==============================================================
# IAM: el Collector necesita leer su config de SSM y escribir a X-Ray.
# ==============================================================
resource "aws_iam_role" "otel_collector_task_role" {
  name = "${var.project_name}-otel-collector-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-otel-collector-task-role"
  }
}

resource "aws_iam_role_policy" "otel_collector_xray" {
  name = "${var.project_name}-otel-collector-xray"
  role = aws_iam_role.otel_collector_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })
}

# El execution role (no el task role) es el que usa el agente ECS para
# leer el parámetro de SSM al armar el comando del contenedor.
resource "aws_iam_role_policy" "otel_collector_config_read" {
  name = "${var.project_name}-otel-collector-config-read"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [aws_ssm_parameter.otel_collector_config.arn]
      }
    ]
  })
}

# ==============================================================
# Networking: solo las tasks de dispatch/triage (y lo que scrapee
# Prometheus más adelante) pueden hablarle al Collector.
# ==============================================================
resource "aws_security_group" "otel_collector" {
  name        = "${var.project_name}-otel-collector-sg"
  description = "Security group for the OTel Collector"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "OTLP gRPC"
    from_port       = 4317
    to_port         = 4317
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "OTLP HTTP"
    from_port       = 4318
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "Prometheus scrape endpoint"
    from_port       = 8889
    to_port         = 8889
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-otel-collector-sg"
  }
}

# ==============================================================
# Service Discovery: dispatch/triage necesitan resolver al Collector
# por un nombre estable (sus IPs de Fargate cambian en cada deploy).
# ==============================================================
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "${var.project_name}.local"
  vpc  = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-internal-namespace"
  }
}

resource "aws_service_discovery_service" "otel_collector" {
  name = "otel-collector"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_cloudwatch_log_group" "otel_collector" {
  name              = "/ecs/${var.project_name}-otel-collector"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-otel-collector-logs"
  }
}

# ==============================================================
# Task Definition + Service
# ==============================================================
resource "aws_ecs_task_definition" "otel_collector" {
  family                   = "${var.project_name}-otel-collector"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.otel_collector_cpu
  memory                   = var.otel_collector_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.otel_collector_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = true
      command   = ["--config=ssm:${aws_ssm_parameter.otel_collector_config.name}"]
      portMappings = [
        { containerPort = 4317, hostPort = 4317, protocol = "tcp" },
        { containerPort = 4318, hostPort = 4318, protocol = "tcp" },
        { containerPort = 8889, hostPort = 8889, protocol = "tcp" },
        { containerPort = 13133, hostPort = 13133, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel_collector.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        { name = "AWS_REGION", value = var.aws_region }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:13133 || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-otel-collector-td"
  }
}

resource "aws_ecs_service" "otel_collector" {
  name            = "${var.project_name}-otel-collector"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.otel_collector.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.otel_collector.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.otel_collector.arn
  }

  depends_on = [
    aws_iam_role_policy.otel_collector_config_read,
    aws_iam_role_policy.otel_collector_xray
  ]

  tags = {
    Name = "${var.project_name}-otel-collector-service"
  }
}
