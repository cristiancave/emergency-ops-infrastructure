.PHONY: help init plan plan-dev plan-staging plan-prod apply apply-dev apply-staging apply-prod destroy fmt validate

help:
	@echo "Emergency Ops - Terraform Commands"
	@echo ""
	@echo "Development:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make plan-dev      - Plan development deployment"
	@echo "  make apply-dev     - Apply development deployment"
	@echo ""
	@echo "Staging:"
	@echo "  make plan-staging  - Plan staging deployment"
	@echo "  make apply-staging - Apply staging deployment"
	@echo ""
	@echo "Production:"
	@echo "  make plan-prod     - Plan production deployment"
	@echo "  make apply-prod    - Apply production deployment (requires confirmation)"
	@echo ""
	@echo "Utilities:"
	@echo "  make fmt           - Format Terraform files"
	@echo "  make validate      - Validate Terraform configuration"
	@echo "  make destroy-dev   - Destroy development infrastructure"
	@echo "  make destroy-staging - Destroy staging infrastructure"

init:
	cd terraform && terraform init

fmt:
	cd terraform && terraform fmt -recursive

validate:
	cd terraform && terraform validate

plan:
	cd terraform && terraform plan -var-file="terraform.tfvars"

plan-dev:
	cd terraform && terraform plan -var-file="environments/dev.tfvars" -out=tfplan-dev

plan-staging:
	cd terraform && terraform plan -var-file="environments/staging.tfvars" -out=tfplan-staging

plan-prod:
	cd terraform && terraform plan -var-file="environments/prod.tfvars" -out=tfplan-prod

apply-dev:
	cd terraform && terraform apply tfplan-dev

apply-staging:
	cd terraform && terraform apply tfplan-staging

apply-prod:
	@echo "WARNING: You are about to apply PRODUCTION changes!"
	@echo "This action cannot be easily undone."
	@read -p "Type 'prod-deploy' to confirm: " confirm; \
	if [ "$$confirm" = "prod-deploy" ]; then \
		cd terraform && terraform apply tfplan-prod; \
	else \
		echo "Deployment cancelled."; \
	fi

destroy-dev:
	cd terraform && terraform destroy -var-file="environments/dev.tfvars"

destroy-staging:
	cd terraform && terraform destroy -var-file="environments/staging.tfvars"

output:
	cd terraform && terraform output

refresh:
	cd terraform && terraform refresh
