# ==============================================================
# PROMETHEUS
# ==============================================================

resource "aws_ssm_parameter" "prometheus_config" {
  name = "/${var.project_name}/prometheus-config"
  type = "String"

  value = yamlencode({
    global = {
      scrape_interval = "15s"
    }
    scrape_configs = [
      {
        job_name = "dispatch-service"
        static_configs = [
          { targets = ["dispatch.${var.project_name}.local:${var.dispatch_container_port}"] }
        ]
      },
      {
        job_name = "triage-service"
        static_configs = [
          { targets = ["triage.${var.project_name}.local:${var.triage_container_port}"] }
        ]
      },
      {
        job_name = "otel-collector"
        static_configs = [
          { targets = ["otel-collector.${var.project_name}.local:8888"] }
        ]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-prometheus-config"
  }
}

resource "aws_iam_role" "prometheus_task_role" {
  name = "${var.project_name}-prometheus-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-prometheus-task-role"
  }
}

resource "aws_iam_role_policy" "prometheus_config_read" {
  name = "${var.project_name}-prometheus-config-read"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [aws_ssm_parameter.prometheus_config.arn]
      }
    ]
  })
}

resource "aws_security_group" "prometheus" {
  name        = "${var.project_name}-prometheus-sg"
  description = "Security group for Prometheus"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Prometheus UI/API, scraped by Grafana"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-prometheus-sg"
  }
}

# Las reglas de ingreso que necesita Prometheus (hacia ecs_tasks y hacia el
# Collector) están definidas inline dentro de esos security groups
# (main.tf / collector.tf), no como aws_security_group_rule sueltas acá:
# mezclar ambos estilos sobre el mismo SG hace que Terraform revierta las
# reglas "sueltas" en cada apply (el recurso aws_security_group administra
# el set completo de reglas y no sabe de las externas).

resource "aws_service_discovery_service" "prometheus" {
  name = "prometheus"

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

resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/${var.project_name}-prometheus"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-prometheus-logs"
  }
}

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.project_name}-prometheus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.prometheus_cpu
  memory                   = var.prometheus_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.prometheus_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prometheus"
      image     = "prom/prometheus:latest"
      essential = true
      # La imagen oficial no sabe leer su config desde una env var, así que
      # sobreescribimos entrypoint+command: escribimos el YAML a disco desde
      # la env var (inyectada por SSM vía "secrets") y recién ahí arrancamos
      # el binario real. Evita tener que hornear una imagen custom.
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "echo \"$PROMETHEUS_CONFIG_YAML\" > /etc/prometheus/prometheus.yml && exec /bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --web.listen-address=:9090"
      ]
      portMappings = [
        { containerPort = 9090, hostPort = 9090, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prometheus.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      secrets = [
        {
          name      = "PROMETHEUS_CONFIG_YAML"
          valueFrom = aws_ssm_parameter.prometheus_config.arn
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9090/-/healthy || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-prometheus-td"
  }
}

resource "aws_ecs_service" "prometheus" {
  name            = "${var.project_name}-prometheus"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.prometheus.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }

  depends_on = [
    aws_iam_role_policy.prometheus_config_read
  ]

  tags = {
    Name = "${var.project_name}-prometheus-service"
  }
}

# ==============================================================
# GRAFANA
# ==============================================================

resource "aws_ssm_parameter" "grafana_datasources" {
  name = "/${var.project_name}/grafana-datasources"
  type = "String"

  value = yamlencode({
    apiVersion = 1
    datasources = [
      {
        name      = "Prometheus"
        type      = "prometheus"
        access    = "proxy"
        url       = "http://prometheus.${var.project_name}.local:9090"
        isDefault = true
      },
      {
        name = "CloudWatch"
        type = "cloudwatch"
        jsonData = {
          authType      = "default"
          defaultRegion = var.aws_region
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-grafana-datasources"
  }
}

resource "aws_ssm_parameter" "grafana_dashboard_provider" {
  name = "/${var.project_name}/grafana-dashboard-provider"
  type = "String"

  value = yamlencode({
    apiVersion = 1
    providers = [
      {
        name                  = "default"
        orgId                 = 1
        folder                = ""
        type                  = "file"
        disableDeletion       = false
        updateIntervalSeconds = 30
        options = {
          path = "/var/lib/grafana/dashboards"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-grafana-dashboard-provider"
  }
}

resource "aws_ssm_parameter" "grafana_dashboard_json" {
  name = "/${var.project_name}/grafana-dashboard-json"
  type = "String"

  value = jsonencode({
    title         = "Emergency Ops - SLIs"
    uid           = "emergency-ops-slis"
    schemaVersion = 39
    time          = { from = "now-1h", to = "now" }
    refresh       = "30s"
    panels = [
      {
        id      = 1
        title   = "Request Rate (traffic)"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 0, y = 0 }
        targets = [
          {
            expr  = "sum by (job) (rate(http_server_request_duration_seconds_count[5m]))"
            refId = "A"
          }
        ]
      },
      {
        id      = 2
        title   = "Error Rate % (errors)"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 0 }
        targets = [
          {
            expr  = "100 * sum by (job) (rate(http_server_request_duration_seconds_count{http_response_status_code=~\"5..\"}[5m])) / sum by (job) (rate(http_server_request_duration_seconds_count[5m]))"
            refId = "A"
          }
        ]
      },
      {
        id      = 3
        title   = "P99 Latency (latency)"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 0, y = 8 }
        targets = [
          {
            expr  = "histogram_quantile(0.99, sum by (job, le) (rate(http_server_request_duration_seconds_bucket[5m])))"
            refId = "A"
          }
        ]
      },
      {
        id      = 4
        title   = "DB Connections Open (saturation)"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 8 }
        targets = [
          {
            expr         = "db_sql_connection_open"
            legendFormat = "triage-service"
            refId        = "A"
          }
        ]
      },
      {
        id         = 5
        title      = "CPU Utilization (ECS)"
        type       = "timeseries"
        datasource = { type = "cloudwatch", uid = "CloudWatch" }
        gridPos    = { h = 8, w = 12, x = 0, y = 16 }
        targets = [
          {
            namespace  = "ECS/ContainerInsights"
            metricName = "CpuUtilized"
            statistic  = "Average"
            dimensions = { ClusterName = var.ecs_cluster_name, ServiceName = "${var.project_name}-dispatch" }
            region     = var.aws_region
            refId      = "A"
          },
          {
            namespace  = "ECS/ContainerInsights"
            metricName = "CpuUtilized"
            statistic  = "Average"
            dimensions = { ClusterName = var.ecs_cluster_name, ServiceName = "${var.project_name}-triage" }
            region     = var.aws_region
            refId      = "B"
          }
        ]
      },
      {
        id      = 6
        title   = "OTel Collector Errors"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 16 }
        targets = [
          {
            expr         = "rate(otelcol_receiver_failed_spans[5m])"
            legendFormat = "receiver failed spans"
            refId        = "A"
          },
          {
            expr         = "rate(otelcol_receiver_refused_spans[5m])"
            legendFormat = "receiver refused spans"
            refId        = "B"
          }
        ]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-grafana-dashboard-json"
  }
}

resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name                    = "${var.project_name}-grafana-admin-password"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name = "${var.project_name}-grafana-admin-password"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = random_password.grafana_admin.result
}

resource "aws_iam_role" "grafana_task_role" {
  name = "${var.project_name}-grafana-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-grafana-task-role"
  }
}

# El datasource de CloudWatch en Grafana usa las credenciales del task role
# (authType=default) para leer métricas de ECS/ContainerInsights.
resource "aws_iam_role_policy" "grafana_cloudwatch_read" {
  name = "${var.project_name}-grafana-cloudwatch-read"
  role = aws_iam_role.grafana_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarmsForMetric",
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "grafana_config_read" {
  name = "${var.project_name}-grafana-config-read"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [
          aws_ssm_parameter.grafana_datasources.arn,
          aws_ssm_parameter.grafana_dashboard_provider.arn,
          aws_ssm_parameter.grafana_dashboard_json.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.grafana_admin_password.arn]
      }
    ]
  })
}

resource "aws_security_group" "grafana" {
  name        = "${var.project_name}-grafana-sg"
  description = "Security group for Grafana"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Grafana UI via ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-grafana-sg"
  }
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project_name}-grafana"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-grafana-logs"
  }
}

resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-grafana-tg"
  }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.main.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.grafana_cpu
  memory                   = var.grafana_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.grafana_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-grafana"
      image     = "grafana/grafana:latest"
      essential = true
      # Igual que Prometheus: escribimos los archivos de provisioning desde
      # las env vars (SSM) antes de arrancar el entrypoint real de la imagen.
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards && echo \"$GRAFANA_DATASOURCES_YAML\" > /etc/grafana/provisioning/datasources/datasources.yaml && echo \"$GRAFANA_DASHBOARD_PROVIDER_YAML\" > /etc/grafana/provisioning/dashboards/provider.yaml && echo \"$GRAFANA_DASHBOARD_JSON\" > /var/lib/grafana/dashboards/slis.json && exec /run.sh"
      ]
      portMappings = [
        { containerPort = 3000, hostPort = 3000, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      secrets = [
        { name = "GRAFANA_DATASOURCES_YAML", valueFrom = aws_ssm_parameter.grafana_datasources.arn },
        { name = "GRAFANA_DASHBOARD_PROVIDER_YAML", valueFrom = aws_ssm_parameter.grafana_dashboard_provider.arn },
        { name = "GRAFANA_DASHBOARD_JSON", valueFrom = aws_ssm_parameter.grafana_dashboard_json.arn },
        { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.grafana_admin_password.arn }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-grafana-td"
  }
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.grafana.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "${var.project_name}-grafana"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.grafana,
    aws_iam_role_policy.grafana_config_read,
    aws_ecs_service.prometheus
  ]

  tags = {
    Name = "${var.project_name}-grafana-service"
  }
}
