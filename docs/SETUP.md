# Guía de Primeros Pasos

> Esta guía asume que estás retomando/operando el ambiente `dev` que ya existe. Si estás
> desplegando desde cero en una cuenta AWS nueva, la sección "Bootstrap desde cero" al final
> cubre eso.

## 📋 Requisitos Previos

1. **AWS Account** con permisos suficientes (IAM, VPC, ECS, RDS, ECR, ALB, Secrets Manager, SSM,
   Cloud Map, X-Ray, CloudWatch)
2. **AWS CLI** configurado con credenciales válidas — solo necesario para operar/debuggear
   manualmente; el despliegue normal no requiere correr nada local (ver más abajo)
3. **Terraform** >= 1.15 — solo si vas a iterar en Terraform localmente
4. **GitHub CLI** (`gh`, opcional) — para ver el estado de los workflows sin ir al navegador

No hace falta Docker instalado a menos que quieras buildear las imágenes localmente para
debugging — el pipeline de CI/CD (GitHub Actions) hace el build normalmente.

## 🚀 Cómo se despliega esto (flujo real)

El despliegue **no es manual**. Es:

1. Código nuevo en [emergency-ops](https://github.com/cristiancave/emergency-ops) → push a
   `main` → GitHub Actions corre `go test ./...`, y si pasa, hace `docker build` (contexto =
   raíz del repo, porque `dispatch` y `triage` comparten el módulo local `pkg/` vía `go.work`)
   y `docker push` a ECR con tag `latest` y con el SHA del commit. Autenticación vía OIDC — sin
   credenciales AWS guardadas en GitHub.
2. Infraestructura nueva en este repo → push a `main` → GitHub Actions corre
   `terraform fmt -check`, `validate`, `plan` y **`apply` automático** contra `dev`.
3. Si solo cambiaste código (paso 1) y las tasks de ECS ya estaban corriendo, hace falta forzar
   que tomen la imagen nueva:
   ```bash
   aws ecs update-service --cluster emergency-ops-cluster --service emergency-ops-dispatch --force-new-deployment --region us-east-1
   aws ecs update-service --cluster emergency-ops-cluster --service emergency-ops-triage --force-new-deployment --region us-east-1
   ```

Ver `docs/GITHUB_OIDC.md` para el detalle de cómo está configurada la autenticación.

## 🛠️ Operar Terraform en tu máquina (para iterar más rápido)

Útil cuando estás debuggeando un cambio y no querés esperar el ciclo completo de CI/CD.

```bash
cd terraform
terraform init                                              # backend S3 ya configurado
terraform plan -var-file="environments/dev.tfvars" -out=tfplan
terraform apply tfplan
terraform output
```

Si aplicaste algo localmente, **el próximo push a `main` va a correr `terraform apply` de
nuevo** contra el mismo state remoto (S3), así que no hay riesgo de "perder" el cambio ni de
duplicar recursos — Terraform reconcilia. Ver `docs/EJEMPLOS.md` para más comandos.

## ✅ Verificar que el ambiente está sano

```bash
# Estado de los 5 servicios ECS
aws ecs describe-services \
  --cluster emergency-ops-cluster \
  --services emergency-ops-dispatch emergency-ops-triage emergency-ops-otel-collector emergency-ops-prometheus emergency-ops-grafana \
  --region us-east-1 \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount}' --output table

# RDS
aws rds describe-db-instances --db-instance-identifier emergency-ops-triage-db --region us-east-1 --query 'DBInstances[0].DBInstanceStatus'

# Outputs de Terraform (URLs, nombres de recursos)
terraform output
```

Probar los servicios (⚠️ el ALB **no** enruta `/dispatch/health` ni `/triage/health` al
healthcheck real — sus reglas de path solo conocen `/dispatch*` y `/triage*`, que van directo a
las rutas de negocio de cada servicio; el healthcheck del ALB pega directo al contenedor, no
pasa por esas reglas). Para probar de verdad, usar las rutas reales:

```bash
ALB_URL=$(terraform output -raw alb_dns_name)

# Clasificar una emergencia
curl -X POST "http://$ALB_URL/triage" -H "Content-Type: application/json" -d '{
  "report_id": "RPT-1", "patient_age": 45,
  "symptoms": ["fiebre alta"], "description": "test"
}'

# Crear un despacho (OJO: incident_latitude/incident_longitude son campos PLANOS, no anidados)
curl -X POST "http://$ALB_URL/dispatch" -H "Content-Type: application/json" -d '{
  "report_id": "RPT-2", "patient_age": 45,
  "symptoms": ["dolor torácico"], "description": "test",
  "incident_latitude": 40.4168, "incident_longitude": -3.7038
}'
```

O mejor, correr el script que genera una mezcla de tráfico válido/inválido de una:
```powershell
.\scripts\generate-demo-traffic.ps1
```

### Ver logs

```bash
aws logs tail /ecs/emergency-ops-dispatch --follow --region us-east-1
aws logs tail /ecs/emergency-ops-triage --follow --region us-east-1
```

### Ver métricas y trazas

- **Grafana**: `http://$ALB_URL:3000` (user `admin`, password en Secrets Manager — ver README)
- **X-Ray**: consola AWS → Traces / Service map
- **Container Insights**: CloudWatch → Container Insights → Clusters → `emergency-ops-cluster`

## 🔄 Cambiar configuración

### Cambiar número de tareas o recursos

```bash
terraform apply -var-file="environments/dev.tfvars" -var="dispatch_desired_count=3"
terraform apply -var-file="environments/dev.tfvars" -var="dispatch_cpu=512" -var="dispatch_memory=1024"
```

### Forzar que ECS tome una imagen nueva de ECR

```bash
aws ecs update-service --cluster emergency-ops-cluster --service emergency-ops-triage --force-new-deployment --region us-east-1
```

## 💰 Pausar/reanudar (no genera costo mientras no lo usás)

```bash
# Pausar
for svc in dispatch triage otel-collector prometheus grafana; do
  aws ecs update-service --cluster emergency-ops-cluster --service "emergency-ops-$svc" --desired-count 0 --region us-east-1
done
aws rds stop-db-instance --db-instance-identifier emergency-ops-triage-db --region us-east-1

# Reanudar
aws rds start-db-instance --db-instance-identifier emergency-ops-triage-db --region us-east-1
for svc in dispatch triage otel-collector prometheus grafana; do
  aws ecs update-service --cluster emergency-ops-cluster --service "emergency-ops-$svc" --desired-count 1 --region us-east-1
done
```

Los NAT Gateways y el ALB siguen corriendo (no tienen estado "pausado", solo se pueden destruir
y recrear) — es el costo fijo menor que queda.

## 🧹 Limpiar Recursos

⚠️ **Cuidado**: esto elimina todos los recursos de AWS, incluida la RDS.

```bash
terraform destroy -var-file="environments/dev.tfvars"
```

## 🆘 Troubleshooting

### Error: "Access Denied" al hacer terraform init/plan

```bash
aws sts get-caller-identity   # verificar que las credenciales activas son las correctas
aws configure                  # o reconfigurar si hace falta
```

### Las tasks no están corriendo / reinician en loop

```bash
aws ecs describe-services --cluster emergency-ops-cluster --services emergency-ops-<nombre> --region us-east-1 --query 'services[0].events[:10]'

TASK_ARN=$(aws ecs list-tasks --cluster emergency-ops-cluster --service-name emergency-ops-<nombre> --region us-east-1 --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster emergency-ops-cluster --tasks "$TASK_ARN" --region us-east-1

aws logs tail /ecs/emergency-ops-<nombre> --since 10m --region us-east-1
```

### ALB no está disponible / target unhealthy

```bash
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN> --region us-east-1
```

### Necesito ver qué hay en la RDS sin exponerla a internet

Ver la sección "Debugging: conectarse a la RDS" en el `README.md` (usa `aws ecs execute-command`
sobre la task de `triage`, que ya tiene ECS Exec habilitado).

## 🏗️ Bootstrap desde cero (cuenta AWS nueva)

Si estás armando esto en una cuenta AWS distinta desde cero (no aplica al ambiente `dev` ya
desplegado):

1. **Backend de Terraform**: crear el bucket S3 + tabla DynamoDB (ver README, sección de
   backend) y actualizar `provider.tf` con el nombre real del bucket.
2. **OIDC para GitHub Actions**: seguir `docs/GITHUB_OIDC.md` — crear el proveedor OIDC, el IAM
   Role con el trust policy scopeado a tus repos, y el secret `AWS_ROLE_TO_ASSUME` en GitHub.
3. **Primer apply**: como todavía no hay imágenes en ECR, el primer `terraform apply` va a fallar
   en los servicios ECS de `dispatch`/`triage` (no hay imagen que pullear). Aplicar primero solo
   ECR (`terraform apply -target=aws_ecr_repository.dispatch -target=aws_ecr_repository.triage`),
   pushear las imágenes (vía el workflow de CI/CD de `emergency-ops`, o manualmente con
   `docker build -f services/dispatch/Dockerfile .` **desde la raíz** de `emergency-ops`), y
   recién ahí aplicar el resto.

## 📚 Recursos Útiles

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [emergency-ops](https://github.com/cristiancave/emergency-ops) — código de los servicios
