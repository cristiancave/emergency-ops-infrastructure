# Ejemplos de Comandos

## Operaciones Básicas

### Inicializar Terraform
```bash
cd terraform
terraform init
```

### Validar la configuración
```bash
terraform validate
terraform fmt -recursive -check
```

### Ver el plan sin aplicar cambios
```bash
# Usando variables por defecto
terraform plan

# Usando archivo de variables específico
terraform plan -var-file="environments/dev.tfvars"

# Guardando el plan a un archivo
terraform plan -var-file="environments/prod.tfvars" -out=tfplan-prod
```

### Aplicar cambios
```bash
# Desde un plan guardado (recomendado para producción)
terraform apply tfplan-prod

# Directamente (pide confirmación)
terraform apply -var-file="environments/staging.tfvars"

# Sin pedir confirmación (use con cuidado)
terraform apply -auto-approve -var-file="environments/dev.tfvars"
```

## Despliegue por Ambiente

### Ambiente de Desarrollo

```bash
# Revisar cambios
terraform plan -var-file="environments/dev.tfvars"

# Aplicar
terraform apply -var-file="environments/dev.tfvars"

# Obtener información de salida
terraform output

# Ver endpoint del ALB
terraform output -raw alb_dns_name

# Ver logs
aws logs tail /ecs/emergency-ops-dispatch --follow

# Destruir (solo para dev)
terraform destroy -var-file="environments/dev.tfvars"
```

### Ambiente de Staging

```bash
# Crear plan
terraform plan -var-file="environments/staging.tfvars" -out=tfplan-staging

# Revisar el plan en detalle
terraform show tfplan-staging

# Aplicar
terraform apply tfplan-staging

# Obtener URLs de servicios
ALB_URL=$(terraform output -raw alb_dns_name)
echo "Dispatch: http://$ALB_URL/dispatch"
echo "Triage: http://$ALB_URL/triage"
```

### Ambiente de Producción

```bash
# Crear plan (sin aplicar automáticamente)
terraform plan -var-file="environments/prod.tfvars" -out=tfplan-prod

# Revisar en detalle
terraform show tfplan-prod

# Hacer un backup del estado actual
terraform state pull > backup-prod-$(date +%Y%m%d-%H%M%S).json

# Aplicar (pide confirmación manual)
terraform apply tfplan-prod
```

## Actualizar Recursos

### Cambiar número de réplicas

```bash
# Aumentar dispatch a 3 instancias
terraform apply \
  -var-file="environments/staging.tfvars" \
  -var="dispatch_desired_count=3" \
  -auto-approve

# Aumentar ambos servicios
terraform apply \
  -var-file="environments/staging.tfvars" \
  -var="dispatch_desired_count=3" \
  -var="triage_desired_count=3" \
  -auto-approve
```

### Cambiar recursos de CPU/Memoria

```bash
# Aumentar recursos del dispatch
terraform apply \
  -var-file="environments/staging.tfvars" \
  -var="dispatch_cpu=512" \
  -var="dispatch_memory=1024" \
  -auto-approve
```

### Cambiar imagen Docker

```bash
# Actualizar imagen del triage service
terraform apply \
  -var-file="environments/prod.tfvars" \
  -var="triage_image_uri=<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:v2.0" \
  -auto-approve
```

### Habilitar/Deshabilitar auto-scaling

```bash
# Deshabilitar auto-scaling en dev
terraform apply \
  -var-file="environments/dev.tfvars" \
  -var="enable_autoscaling=false" \
  -auto-approve
```

## Verificación y Debugging

### Ver el estado actual
```bash
# Ver todo el estado (verboso)
terraform show

# Ver solo el plan actual sin aplicar
terraform plan -var-file="environments/dev.tfvars"

# Ver un recurso específico
terraform state show aws_ecs_service.dispatch
```

### Listar todos los recursos
```bash
terraform state list

# Filtrar
terraform state list | grep dispatch
```

### Obtener información de recursos
```bash
# Ver detalles de un servicio ECS
terraform state show 'aws_ecs_service.dispatch'

# Ver detalles del ALB
terraform state show 'aws_lb.main'

# Ver todas las variables usadas
terraform tfvars
```

### Ver outputs
```bash
# Ver todos
terraform output

# Ver uno específico
terraform output alb_dns_name

# Sin comillas
terraform output -raw alb_dns_name

# Como JSON
terraform output -json
```

## Gestión de Estado

### Backup del estado
```bash
# Backup local
terraform state pull > terraform.state.backup

# Backup con timestamp
terraform state pull > backup-$(date +%Y%m%d-%H%M%S).json
```

### Forzar refresh del estado
```bash
terraform refresh -var-file="environments/dev.tfvars"
```

### Ver historial de cambios
```bash
terraform state list -state=backup-20240815-120000.json
```

## Limpieza y Destrucción

### Destruir recursos específicos
```bash
# Destruir solo el auto-scaling del dispatch
terraform destroy \
  -var-file="environments/dev.tfvars" \
  -target='aws_appautoscaling_target.dispatch' \
  -auto-approve
```

### Destruir todo un ambiente
```bash
# Solicita confirmación
terraform destroy -var-file="environments/dev.tfvars"

# Sin confirmación (¡cuidado!)
terraform destroy -var-file="environments/dev.tfvars" -auto-approve
```

### Limpiar archivos temporales
```bash
rm tfplan tfplan-*
rm .terraform/lock.hcl
rm -rf .terraform/
```

## Integración con AWS CLI

### Obtener endpoints

```bash
# Desde Terraform
ALB_URL=$(terraform output -raw alb_dns_name)

# Desde AWS CLI
ALB_URL=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`emergency-ops-alb`].DNSName' \
  --output text)

# Usar en curl
curl http://$ALB_URL/triage/health
```

### Ver services

```bash
aws ecs list-services --cluster emergency-ops-cluster

aws ecs describe-services \
  --cluster emergency-ops-cluster \
  --services emergency-ops-dispatch emergency-ops-triage
```

### Actualizar deployment (fuerza nueva versión)

```bash
# Fuerza redeploy del dispatch
aws ecs update-service \
  --cluster emergency-ops-cluster \
  --service emergency-ops-dispatch \
  --force-new-deployment

# Esperar a que se actualice
aws ecs wait services-stable \
  --cluster emergency-ops-cluster \
  --services emergency-ops-dispatch
```

### Ver logs
```bash
# Últimas 50 líneas
aws logs tail /ecs/emergency-ops-triage --max-items 50

# Últimas 10 minutos
aws logs tail /ecs/emergency-ops-dispatch --since 10m --follow

# Filtrar por error
aws logs filter-log-events \
  --log-group-name /ecs/emergency-ops-dispatch \
  --filter-pattern "ERROR"
```

## GitHub Actions / CI/CD

### Workflow manual
```bash
# Ver status del workflow
gh workflow list

# Ver runs del workflow terraform
gh run list -w terraform.yml

# Ver detalles de un run
gh run view <RUN_ID> --log
```

### Triggear manualmente
```bash
# Trigger manual del workflow
gh workflow run terraform.yml -f environment=dev
```

## Troubleshooting

### Debug detallado
```bash
# Ver mensajes de debug
TF_LOG=DEBUG terraform plan -var-file="environments/dev.tfvars"

# Guardar logs
TF_LOG=DEBUG terraform plan -var-file="environments/dev.tfvars" > debug.log 2>&1
```

### Validar sintaxis HCL
```bash
terraform fmt -recursive -check
```

### Ver qué cambiaría
```bash
terraform plan -var-file="environments/dev.tfvars" | grep "~\|+"
```

### Recrear un recurso específico
```bash
# Marcar para destruir y recrear
terraform taint aws_ecs_task_definition.dispatch

# Aplicar (lo destruye y recrea)
terraform apply -var-file="environments/dev.tfvars"
```
