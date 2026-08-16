# Guía de Primeros Pasos

## 📋 Requisitos Previos

1. **AWS Account**: Cuenta AWS activa con permisos de administrador
2. **Terraform**: Versión 1.0 o superior
3. **AWS CLI**: Configurado con credenciales válidas
4. **Docker**: Para compilar las imágenes de los microservicios

## 🚀 Configuración Inicial

### 1. Clonar el repositorio

```bash
git clone <repo-url>
cd emergency-ops-infrastructure
```

### 2. Inicializar Terraform

```bash
cd terraform
terraform init
```

Esto descargará los plugins necesarios y configurará el estado local.

### 3. Validar la configuración

```bash
terraform validate
terraform fmt -recursive
```

### 4. Revisar qué se va a crear

Para el ambiente de **desarrollo**:

```bash
terraform plan -var-file="environments/dev.tfvars"
```

Esto mostrará todos los recursos que se crearán sin modificar nada.

## 🐳 Preparar las Imágenes Docker

Antes de desplegar, necesitas compilar y subir las imágenes Docker a ECR.

### 1. Crear repositorios ECR

```bash
aws ecr create-repository \
  --repository-name emergency-ops-dispatch \
  --region us-east-1

aws ecr create-repository \
  --repository-name emergency-ops-triage \
  --region us-east-1
```

### 2. Obtener credenciales de ECR

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

(Reemplaza `<ACCOUNT_ID>` con tu ID de cuenta AWS)

### 3. Compilar y subir las imágenes

```bash
# Desde la carpeta del proyecto emergency-ops

# Dispatch
docker build -t dispatch-service:latest services/dispatch/
docker tag dispatch-service:latest \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-dispatch:latest
docker push \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-dispatch:latest

# Triage
docker build -t triage-service:latest services/triage/
docker tag triage-service:latest \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:latest
docker push \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:latest
```

## 🛠️ Desplegar la Infraestructura

### Opción 1: Con Plan (Recomendado)

```bash
cd terraform

# Crear plan
terraform plan \
  -var-file="environments/dev.tfvars" \
  -out=tfplan

# Aplicar
terraform apply tfplan
```

### Opción 2: Usando Make

```bash
make plan-dev
make apply-dev
```

### Opción 3: Usando Terraform Directamente

```bash
terraform apply -var-file="environments/dev.tfvars"
```

## ✅ Verificar el Despliegue

### 1. Obtener los outputs

```bash
terraform output
```

Esto mostrará:
- DNS name del ALB
- Endpoints de los servicios
- Log groups de CloudWatch

### 2. Probar los servicios

```bash
# Obtener la URL del ALB
ALB_URL=$(terraform output -raw alb_dns_name)

# Probar dispatch
curl http://$ALB_URL/dispatch/health

# Probar triage
curl http://$ALB_URL/triage/health
```

### 3. Ver logs en CloudWatch

```bash
# Ver logs del dispatch
aws logs tail /ecs/emergency-ops-dispatch --follow

# Ver logs del triage
aws logs tail /ecs/emergency-ops-triage --follow
```

## 📊 Monitoreo

### CloudWatch Metrics

1. Ir a AWS Console → CloudWatch → Dashboards
2. Ver métricas de ECS en tiempo real

### Container Insights

1. CloudWatch → Container Insights → Clusters
2. Seleccionar `emergency-ops-cluster`

### Health Checks

```bash
# Ver estado de tasks
aws ecs describe-services \
  --cluster emergency-ops-cluster \
  --services emergency-ops-dispatch emergency-ops-triage \
  --region us-east-1
```

## 🔄 Actualizar Configuración

### Cambiar número de tareas

```bash
terraform apply \
  -var-file="environments/dev.tfvars" \
  -var="dispatch_desired_count=3"
```

### Cambiar recursos de CPU/Memoria

```bash
terraform apply \
  -var-file="environments/dev.tfvars" \
  -var="dispatch_cpu=512" \
  -var="dispatch_memory=1024"
```

### Actualizar imágenes Docker

1. Compilar y subir nueva imagen a ECR
2. Actualizar la imagen en ECR
3. Recriar las tasks:

```bash
aws ecs update-service \
  --cluster emergency-ops-cluster \
  --service emergency-ops-dispatch \
  --force-new-deployment \
  --region us-east-1
```

## 🧹 Limpiar Recursos

⚠️ **Cuidado**: Esto eliminará todos los recursos de AWS creados.

```bash
terraform destroy -var-file="environments/dev.tfvars"
```

## 🔐 Seguridad

### Mejores Prácticas

1. **Nunca comitear credenciales**: Usar `terraform.tfvars.local` (en .gitignore)
2. **Backend remoto**: Usar S3 + DynamoDB para estado compartido
3. **RBAC en AWS**: Usar IAM roles con permisos mínimos
4. **Tagging**: Etiquetar todos los recursos
5. **Backups**: Regular backups de la base de datos (si agregan RDS)

### Configurar Backend Remoto

Ver `README.md` en la sección "Configuración de Backend Remoto"

## 🆘 Troubleshooting

### Error: "Access Denied" al hacer terraform init

```bash
# Verificar credenciales AWS
aws sts get-caller-identity

# Configurar nuevas credenciales
aws configure
```

### Las tasks no están corriendo

```bash
# Ver logs detallados
aws ecs describe-tasks \
  --cluster emergency-ops-cluster \
  --tasks <TASK_ARN> \
  --region us-east-1

# Ver logs en CloudWatch
aws logs get-log-events \
  --log-group-name /ecs/emergency-ops-dispatch \
  --log-stream-name <LOG_STREAM>
```

### ALB no está disponible

```bash
# Verificar target groups
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --region us-east-1
```

## 📚 Recursos Útiles

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Emergency Ops GitHub Repository](https://github.com/your-org/emergency-ops)

## 📞 Soporte

Para problemas o preguntas:
1. Revisar los logs de CloudWatch
2. Usar `terraform show` para ver el estado actual
3. Revisar los Architecture Decision Records (ADR) en `docs/ADR.md`
