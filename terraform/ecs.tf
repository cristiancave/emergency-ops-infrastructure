# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

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
    Name = "${var.project_name}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

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
    Name = "${var.project_name}-ecs-task-role"
  }
}

# Dispatch Service - Task Definition
resource "aws_ecs_task_definition" "dispatch" {
  family                   = "${var.project_name}-dispatch"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.dispatch_cpu
  memory                   = var.dispatch_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dispatch"
      image     = var.dispatch_image_uri
      essential = true
      portMappings = [
        {
          containerPort = var.dispatch_container_port
          hostPort      = var.dispatch_container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dispatch.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        {
          name  = "DISPATCH_PORT"
          value = tostring(var.dispatch_container_port)
        },
        {
          name  = "TRIAGE_SERVICE_URL"
          value = "http://${aws_lb.main.dns_name}"
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.dispatch_container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-dispatch-td"
  }
}

# Dispatch Service
resource "aws_ecs_service" "dispatch" {
  name            = "${var.project_name}-dispatch"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.dispatch.arn
  desired_count   = var.dispatch_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dispatch.arn
    container_name   = "${var.project_name}-dispatch"
    container_port   = var.dispatch_container_port
  }

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role.ecs_task_execution_role
  ]

  tags = {
    Name = "${var.project_name}-dispatch-service"
  }
}

# Dispatch Auto-scaling Target
resource "aws_appautoscaling_target" "dispatch" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.dispatch.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Dispatch Auto-scaling Policy (CPU)
resource "aws_appautoscaling_policy" "dispatch_cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.project_name}-dispatch-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dispatch[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dispatch[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dispatch[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_target / 100
  }
}

# Dispatch Auto-scaling Policy (Memory)
resource "aws_appautoscaling_policy" "dispatch_memory" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.project_name}-dispatch-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dispatch[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dispatch[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dispatch[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = var.memory_target / 100
  }
}

# Triage Service - Task Definition
resource "aws_ecs_task_definition" "triage" {
  family                   = "${var.project_name}-triage"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.triage_cpu
  memory                   = var.triage_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-triage"
      image     = var.triage_image_uri
      essential = true
      portMappings = [
        {
          containerPort = var.triage_container_port
          hostPort      = var.triage_container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.triage.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        {
          name  = "TRIAGE_PORT"
          value = tostring(var.triage_container_port)
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.triage_container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-triage-td"
  }
}

# Triage Service
resource "aws_ecs_service" "triage" {
  name            = "${var.project_name}-triage"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.triage.arn
  desired_count   = var.triage_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.triage.arn
    container_name   = "${var.project_name}-triage"
    container_port   = var.triage_container_port
  }

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role.ecs_task_execution_role
  ]

  tags = {
    Name = "${var.project_name}-triage-service"
  }
}

# Triage Auto-scaling Target
resource "aws_appautoscaling_target" "triage" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.triage.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Triage Auto-scaling Policy (CPU)
resource "aws_appautoscaling_policy" "triage_cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.project_name}-triage-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.triage[0].resource_id
  scalable_dimension = aws_appautoscaling_target.triage[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.triage[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_target / 100
  }
}

# Triage Auto-scaling Policy (Memory)
resource "aws_appautoscaling_policy" "triage_memory" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.project_name}-triage-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.triage[0].resource_id
  scalable_dimension = aws_appautoscaling_target.triage[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.triage[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = var.memory_target / 100
  }
}
