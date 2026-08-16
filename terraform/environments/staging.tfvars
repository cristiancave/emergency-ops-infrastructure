aws_region         = "us-east-1"
environment        = "staging"
project_name       = "emergency-ops"
availability_zones = 2

# VPC
vpc_cidr = "10.1.0.0/16"

# Dispatch Service
dispatch_cpu            = 512
dispatch_memory         = 1024
dispatch_desired_count  = 2
dispatch_container_port = 8080

# Triage Service
triage_cpu            = 512
triage_memory         = 1024
triage_desired_count  = 2
triage_container_port = 8081

# Auto-scaling
enable_autoscaling = true
min_capacity       = 2
max_capacity       = 4
cpu_target         = 70
memory_target      = 80
