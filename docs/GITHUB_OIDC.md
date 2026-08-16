# GitHub Actions - AWS OIDC Configuration

Para usar OIDC en lugar de almacenar credenciales AWS directamente, sigue estos pasos:

## 1. Crear IAM Role en AWS

### Opción A: Via AWS CLI

```bash
#!/bin/bash

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_OWNER="your-github-username"  # Cambiar
REPO_NAME="emergency-ops-infrastructure"  # Cambiar

# Crear trust policy
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$REPO_OWNER/$REPO_NAME:ref:refs/heads/*"
        }
      }
    }
  ]
}
EOF

# Crear IAM role
aws iam create-role \
  --role-name github-actions-emergency-ops-role \
  --assume-role-policy-document file://trust-policy.json

# Adjuntar política de permisos
aws iam put-role-policy \
  --role-name github-actions-emergency-ops-role \
  --policy-name terraform-permissions \
  --policy-document file://permissions-policy.json
```

### Opción B: Via AWS Console

1. Ir a IAM → Identity providers → Add provider
2. Seleccionar OpenID Connect
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. Crear role con trust policy que confíe en este provider

## 2. Crear Política de Permisos

Crear archivo `permissions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ecs:*",
        "elasticloadbalancing:*",
        "logs:*",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:ListRolePolicies",
        "iam:GetRole"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-state-emergency-ops",
        "arn:aws:s3:::terraform-state-emergency-ops/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-locks"
    }
  ]
}
```

## 3. Adjuntar Política al Role

```bash
aws iam put-role-policy \
  --role-name github-actions-emergency-ops-role \
  --policy-name terraform-permissions \
  --policy-document file://permissions-policy.json
```

## 4. Configurar GitHub Secrets

En tu repositorio GitHub:
1. Ir a Settings → Secrets and variables → Actions
2. Crear `AWS_ROLE_TO_ASSUME` con el valor:
   ```
   arn:aws:iam::<ACCOUNT_ID>:role/github-actions-emergency-ops-role
   ```

Reemplaza `<ACCOUNT_ID>` con tu ID de cuenta AWS.

## 5. Actualizar GitHub Workflow

El archivo `.github/workflows/terraform.yml` ya está configurado para usar OIDC.

Verifica que incluya:

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
    aws-region: ${{ env.AWS_REGION }}
```

## 6. Verificar la Configuración

```bash
# Ver el role creado
aws iam get-role --role-name github-actions-emergency-ops-role

# Ver la política adjunta
aws iam get-role-policy \
  --role-name github-actions-emergency-ops-role \
  --policy-name terraform-permissions
```

## Ventajas de OIDC

✅ No almacena credenciales AWS en GitHub
✅ Credenciales temporales (duran 1 hora)
✅ Auditoría completa en CloudTrail
✅ Riesgo reducido de credential leaks
✅ Cumple con estándares de seguridad

## Troubleshooting

### Error: "User is not authorized to perform: sts:AssumeRoleWithWebIdentity"

- Verificar que el trust policy está correctamente configurado
- Asegurarse que el ID de cuenta es correcto
- Verificar que el proveedor OIDC está creado

### Error: "The OIDC token can't be exchanged for AWS credentials"

- Verificar que `AWS_ROLE_TO_ASSUME` secret está configurado
- Verificar que el role name es exacto
- Esperar unos minutos después de crear el role

### El workflow se ejecuta pero falla al acceder a AWS

- Verificar que la política adjunta tiene los permisos necesarios
- Ver CloudTrail para denials específicos
- Aumentar los permisos si es necesario

## Referencias

- [GitHub Actions - AWS OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS IAM OIDC Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS Actions - Configure AWS Credentials](https://github.com/aws-actions/configure-aws-credentials)
