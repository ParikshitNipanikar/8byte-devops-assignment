# Terraform layout

Terraform is intentionally split by responsibility so each file has one easy explanation:

| File | Purpose |
|---|---|
| `backend.tf` | Declares this assignment account's remote S3 backend |
| `main.tf` | Core VPC, EKS, RDS, and ECR resources |
| `iam-load-balancer-controller.tf` | IRSA permissions for the ALB controller |
| `iam-github-actions.tf` | GitHub OIDC role and deployment permissions |
| `eks-addons.tf` | CloudWatch observability add-on and log groups |
| `variables.tf` | Configurable inputs |
| `outputs.tf` | Values consumed by Docker, kubectl, Helm, and CI |

Run the state bootstrap first:

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cp terraform-bootstrap/terraform.tfvars.example terraform-bootstrap/terraform.tfvars
sed -i '' "s/REPLACE_WITH_AWS_ACCOUNT_ID/$ACCOUNT_ID/" terraform-bootstrap/terraform.tfvars
terraform -chdir=terraform-bootstrap init
terraform -chdir=terraform-bootstrap plan -out=bootstrap.tfplan
terraform -chdir=terraform-bootstrap apply bootstrap.tfplan
```

Then initialize and apply the main configuration:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
sed -i '' "s/REPLACE_WITH_AWS_ACCOUNT_ID/$ACCOUNT_ID/" terraform/terraform.tfvars
terraform -chdir=terraform init -reconfigure
terraform -chdir=terraform plan -out=infra.tfplan
terraform -chdir=terraform apply infra.tfplan
```

The small `terraform-bootstrap/` directory exists only because an S3 bucket cannot store its own Terraform state before it exists. It is not a second application environment.

The backend is written directly in `backend.tf` because this is a single-account assignment. For several environments, use separate partial backend configuration files instead.
