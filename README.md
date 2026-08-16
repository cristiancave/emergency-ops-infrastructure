# Emergency Ops - Infrastructure as Code

Infraestructura en AWS para desplegar los microservicios de Emergency Ops usando Terraform.

## 📋 Requisitos

- Terraform >= 1.0
- AWS CLI configurado con credenciales válidas
- Cuenta AWS activa

## 🏗️ Estructura del Proyecto

```
terraform/
├── provider.tf              # Configuración de AWS provider
├── variables.tf             # Definición de variables
├── main.tf                  # VPC, Subnets, Security Groups, ALB
├── ecs.tf                   # ECS Cluster, Task Definitions, Services
├── outputs.tf               # Outputs de la infraestructura
├── terraform.tfvars         # Valores por defecto
└── environments/
    ├── dev.tfvars          # Variables para desarrollo
    ├── staging.tfvars      # Variables para staging
    └── prod.tfvars         # Variables para producción
```

## 🚀 Cómo Usar

### 1. Inicializar Terraform

```bash
cd terraform
terraform init
```

### 2. Validar la Configuración

```bash
terraform validate
terraform fmt -recursive
```

### 3. Planificar el Despliegue (Desarrollo)

```bash
terraform plan -var-file="environments/dev.tfvars" -out=tfplan
```

### 4. Aplicar los Cambios

```bash
terraform apply tfplan
```

### 5. Obtener los Outputs

```bash
terraform output
```

## 🌍 Ambientes

### Desarrollo
```bash
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

### Staging
```bash
terraform plan -var-file="environments/staging.tfvars"
terraform apply -var-file="environments/staging.tfvars"
```

### Producción
```bash
terraform plan -var-file="environments/prod.tfvars"
terraform apply -var-file="environments/prod.tfvars"
```

## 📊 Recursos Creados

### Networking
- VPC con CIDR configurable
- 2-3 Public Subnets (una por AZ)
- 2-3 Private Subnets (una por AZ)
- NAT Gateways para salida a internet
- Internet Gateway
- Route Tables

### Compute (ECS)
- ECS Cluster con CloudWatch Container Insights
- 2 Task Definitions (Dispatch + Triage)
- 2 ECS Services con Fargate
- Auto-scaling configurable por servicio
- Health checks integrados

### Load Balancing
- Application Load Balancer (ALB)
- 2 Target Groups (uno por servicio)
- Path-based routing (/dispatch, /triage)

### Logging & Monitoring
- CloudWatch Log Groups
- CloudWatch Container Insights

### Security
- Security Groups con reglas específicas
- IAM Roles y Policies
- No public IPs en tareas (excepto ALB)

## 🔒 Configuración de Backend Remoto

Para usar S3 como almacenamiento del estado (recomendado en equipos):

1. Crear bucket S3 y tabla DynamoDB:
```bash
aws s3api create-bucket --bucket terraform-state-emergency-ops --region us-east-1
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

2. Descomentar backend en `provider.tf`:
```hcl
backend "s3" {
  bucket         = "terraform-state-emergency-ops"
  key            = "emergency-ops/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-locks"
}
```

3. Reinicializar:
```bash
terraform init
```

## 📝 Variables Principales

| Variable | Descripción | Default |
|----------|-------------|---------|
| `aws_region` | Región AWS | us-east-1 |
| `environment` | Ambiente (dev/staging/prod) | dev |
| `vpc_cidr` | CIDR del VPC | 10.0.0.0/16 |
| `dispatch_cpu` | CPU para task de Dispatch | 256 |
| `dispatch_memory` | Memoria (MB) para Dispatch | 512 |
| `triage_cpu` | CPU para task de Triage | 256 |
| `triage_memory` | Memoria (MB) para Triage | 512 |
| `enable_autoscaling` | Habilitar auto-scaling | true |

## 🧹 Destruir la Infraestructura

```bash
terraform destroy -var-file="environments/dev.tfvars"
```

## 📚 Despliegue de Imágenes Docker

Antes de aplicar Terraform, necesitas:

1. Crear ECR repositories:
```bash
aws ecr create-repository --repository-name emergency-ops-dispatch --region us-east-1
aws ecr create-repository --repository-name emergency-ops-triage --region us-east-1
```

2. Compilar y push de imágenes:
```bash
cd emergency-ops
docker build -t dispatch-service services/dispatch/
docker build -t triage-service services/triage/

# Tag y push a ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account_id>.dkr.ecr.us-east-1.amazonaws.com
docker tag dispatch-service:latest <account_id>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-dispatch:latest
docker tag triage-service:latest <account_id>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:latest

docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-dispatch:latest
docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:latest
```

3. Actualizar variables con URIs del ECR:
```bash
terraform apply \
  -var-file="environments/dev.tfvars" \
  -var="dispatch_image_uri=<account_id>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-dispatch:latest" \
  -var="triage_image_uri=<account_id>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:latest"
```

## 🔍 Monitoreo

- **CloudWatch Logs**: Ver logs de servicios en `/ecs/emergency-ops-dispatch` y `/ecs/emergency-ops-triage`
- **Container Insights**: Métricas de contenedores en CloudWatch
- **ALB Metrics**: Health checks y request counts en CloudWatch

## 📞 Soporte

Para más información sobre Terraform: https://www.terraform.io/docs
Para más información sobre AWS ECS: https://docs.aws.amazon.com/ecs/
