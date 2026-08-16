aws_region         = "us-east-1"
environment        = "prod"
project_name       = "emergency-ops"
availability_zones = 3

# VPC
vpc_cidr = "10.2.0.0/16"

# Dispatch Service
dispatch_cpu            = 1024
dispatch_memory         = 2048
dispatch_desired_count  = 3
dispatch_container_port = 8080

# Triage Service
triage_cpu            = 1024
triage_memory         = 2048
triage_desired_count  = 3
triage_container_port = 8081

# Auto-scaling
enable_autoscaling = true
min_capacity       = 3
max_capacity       = 8
cpu_target         = 70
memory_target      = 80
