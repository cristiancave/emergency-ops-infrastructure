# Architecture Decision Records (ADR)

## ADR-001: Infrastructure as Code with Terraform

### Status
ACCEPTED

### Context
We need to manage AWS infrastructure for the Emergency Ops microservices platform in a reproducible, version-controlled, and scalable manner.

### Decision
Use Terraform as the Infrastructure as Code tool for AWS management.

### Rationale
- **Multi-cloud capability**: Not locked into AWS
- **Large community**: Abundant resources and modules
- **State management**: Clear separation of concerns
- **Version control**: Full infrastructure history
- **Team collaboration**: Easy to review in pull requests

### Consequences
- Terraform state must be managed carefully
- Requires AWS IAM credentials
- Need to set up S3 backend for team environments
- Regular state backups recommended

---

## ADR-002: ECS Fargate for Container Orchestration

### Status
ACCEPTED

### Context
We need to run containerized microservices (Go applications) in AWS with minimal operational overhead.

### Decision
Use AWS ECS (Elastic Container Service) with Fargate launch type.

### Rationale
- **Serverless**: No need to manage EC2 instances
- **Cost-efficient**: Pay only for what you use
- **Easy integration**: ALB, Auto-scaling, CloudWatch
- **AWS-native**: Native integration with other AWS services
- **Security**: Automatic patching and updates

### Consequences
- Locked to AWS ecosystem
- Limited customization compared to Kubernetes
- Container size limited to 10GB
- Network throughput limits per task

---

## ADR-003: Application Load Balancer with Path-based Routing

### Status
ACCEPTED

### Context
Multiple microservices need to be exposed through a single entry point with intelligent routing.

### Decision
Use AWS Application Load Balancer (ALB) with path-based routing rules.

### Rationale
- **Path-based routing**: /dispatch → dispatch service, /triage → triage service
- **Auto-scaling friendly**: Works seamlessly with ECS Auto Scaling
- **Health checks**: Built-in health check capabilities
- **Cost**: Single ALB for multiple services

### Consequences
- Requires health check endpoints on services
- Path rewriting needed if services don't expect paths
- CloudWatch monitoring must be configured

---

## ADR-004: Multi-environment Strategy (Dev, Staging, Prod)

### Status
ACCEPTED

### Context
We need different configurations and resource allocations for different deployment environments.

### Decision
Separate tfvars files for dev, staging, and prod with different resource allocations.

### Rationale
- **Cost optimization**: Dev uses minimal resources, Prod uses HA setup
- **Testing**: Staging matches production closely
- **Risk isolation**: Dev/staging failures don't affect production
- **Gradual rollout**: Changes tested in multiple environments

### Consequences
- More tfvars files to maintain
- Need to track which file is used in each environment
- Risk of applying wrong environment configuration

---

## ADR-005: Auto-scaling Policy Based on CPU/Memory

### Status
ACCEPTED

### Context
Need automatic scaling to handle variable load on microservices.

### Decision
Use Target Tracking Scaling policies based on CPU and memory utilization.

### Rationale
- **Automatic**: No manual intervention needed
- **Predictable costs**: Scales up only when needed
- **Dual metrics**: CPU + Memory for comprehensive coverage
- **Easy tuning**: Simple adjustable thresholds

### Consequences
- Must ensure proper resource requests/limits
- Health checks must be accurate
- Scaling takes time (may not handle sudden spikes)

---

## ADR-006: CloudWatch Logs for Container Logging

### Status
ACCEPTED

### Context
Microservices need centralized, accessible logging for debugging and monitoring.

### Decision
Use CloudWatch Logs as the log driver for ECS containers.

### Rationale
- **AWS-native**: Seamless integration with ECS
- **No agent needed**: Built-in log driver
- **Searchable**: Full-text search capabilities
- **Retention policies**: Automatic cleanup

### Consequences
- Logs only available within AWS
- CloudWatch Insights required for complex queries
- Additional AWS costs for log storage

---

## ADR-007: VPC with Public/Private Subnets

### Status
ACCEPTED

### Context
Need proper network segmentation for security and best practices.

### Decision
Create VPC with 2-3 public subnets (ALB) and 2-3 private subnets (ECS tasks) per AZ.

### Rationale
- **Security**: ECS tasks not exposed to internet
- **HA**: Multiple availability zones for fault tolerance
- **NAT Gateways**: Secure outbound internet access
- **Best practices**: Following AWS Well-Architected Framework

### Consequences
- Increased infrastructure complexity
- NAT Gateway costs for outbound traffic
- More subnets to manage

