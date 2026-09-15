# 8Byte DevOps Assignment

AWS infrastructure and deployment automation for a Flask/nginx application on EKS with PostgreSQL, CI/CD, centralized logging, Prometheus, Grafana, and CloudWatch.

Deployment status: currently destroyed. AWS generates a new ALB hostname after each deployment.

For a command-by-command deployment with explanations, use [INTERVIEW_RUNBOOK.md](INTERVIEW_RUNBOOK.md).

## Architecture

```text
Internet
   |
Public ALB
   |-- /              -> frontend Service -> nginx Pods
   |-- /health        -> backend Service  -> Flask Pods
   `-- /api           -> backend Service  -> Flask Pods -> private RDS PostgreSQL

VPC across ap-south-1a and ap-south-1b
   Public subnets:  ALB, Internet Gateway, one NAT Gateway
   Private subnets: EKS worker nodes, application Pods, RDS

Prometheus/Grafana: Kubernetes, application RED, and PostgreSQL metrics
CloudWatch: centralized application, host, dataplane, and control-plane logs
```

## Repository layout

```text
terraform-bootstrap/          S3 remote-state bucket
terraform/                    VPC, EKS, RDS, ECR, IAM, and centralized logs
helm/8byte-app/               App, PostgreSQL exporter, Services, and ALB Ingress
helm/values/                  ALB controller and monitoring values
app/backend/                  Flask API, tests, metrics, and Dockerfile
app/frontend/                 nginx frontend and Dockerfile
.github/workflows/            PR tests and main-branch deployment
```

## Prerequisites

- AWS CLI configured for the intended account
- Terraform `>= 1.10, < 2.0`
- Docker, kubectl, Helm, Trivy, jq, and Git
- AWS permission to create VPC, EKS, EC2, RDS, ECR, IAM, S3, and CloudWatch resources

Verify identity first:

```bash
aws sts get-caller-identity
export AWS_REGION=ap-south-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## 1. Bootstrap remote state

Terraform cannot use an S3 backend until the bucket exists, so this small configuration runs first.

```bash
cp terraform-bootstrap/terraform.tfvars.example terraform-bootstrap/terraform.tfvars
sed -i '' "s/REPLACE_WITH_AWS_ACCOUNT_ID/$ACCOUNT_ID/" terraform-bootstrap/terraform.tfvars
terraform -chdir=terraform-bootstrap init
terraform -chdir=terraform-bootstrap fmt -check
terraform -chdir=terraform-bootstrap validate
terraform -chdir=terraform-bootstrap plan -out=bootstrap.tfplan
terraform -chdir=terraform-bootstrap apply bootstrap.tfplan
```

This creates an encrypted, versioned, private bucket named `8byte-terraform-state-<ACCOUNT_ID>`. State locking uses Terraform's native S3 lock file.

## 2. Provision AWS infrastructure

Create the ignored, account-specific variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
sed -i '' "s/REPLACE_WITH_AWS_ACCOUNT_ID/$ACCOUNT_ID/" terraform/terraform.tfvars
sed -i '' "s|YOUR_GITHUB_USERNAME@YOUR_GITHUB_OWNER_ID/8byte-devops-assignment@YOUR_REPOSITORY_ID|ParikshitNipanikar@111178325/8byte-devops-assignment@1350420946|" terraform/terraform.tfvars
```

Initialize, validate, review, and apply:

```bash
terraform -chdir=terraform init -reconfigure
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=infra.tfplan
terraform -chdir=terraform show -no-color infra.tfplan
terraform -chdir=terraform apply infra.tfplan
terraform -chdir=terraform output
```

Terraform creates the two-AZ VPC, private EKS nodes, private PostgreSQL RDS, ECR, IAM roles, CloudWatch observability add-on, and centralized log groups.

## 3. Connect to EKS

```bash
export EKS_CLUSTER=$(terraform -chdir=terraform output -raw eks_cluster_name)
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION" --alias 8byte-eks
kubectl --context 8byte-eks get nodes
```

## 4. Build, scan, and push images

```bash
export BACKEND_ECR=$(terraform -chdir=terraform output -raw ecr_repository_url)
export FRONTEND_ECR=$(terraform -chdir=terraform output -raw frontend_ecr_repository_url)
export IMAGE_TAG="$(git rev-parse --short=12 HEAD)-$(date -u +%Y%m%d%H%M%S)"
```

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
docker build --pull --platform linux/amd64 -t "$BACKEND_ECR:$IMAGE_TAG" app/backend
docker build --pull --platform linux/amd64 -t "$FRONTEND_ECR:$IMAGE_TAG" app/frontend
trivy image --exit-code 1 --severity HIGH,CRITICAL "$BACKEND_ECR:$IMAGE_TAG"
trivy image --exit-code 1 --severity HIGH,CRITICAL "$FRONTEND_ECR:$IMAGE_TAG"
docker push "$BACKEND_ECR:$IMAGE_TAG"
docker push "$FRONTEND_ECR:$IMAGE_TAG"
```

## 5. Create the database Secret

```bash
export RDS_HOST=$(terraform -chdir=terraform output -raw rds_address)
export RDS_SECRET_ARN=$(terraform -chdir=terraform output -raw rds_master_secret_arn)
```

The password is streamed directly from Secrets Manager and is not printed or stored in Helm values:

```bash
aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$RDS_SECRET_ARN" \
  --query SecretString \
  --output text | \
  jq -jr '.password' | \
  kubectl --context 8byte-eks -n default create secret generic db-credentials \
    --from-file=password=/dev/stdin --dry-run=client -o yaml | \
  kubectl --context 8byte-eks apply -f -
```

## 6. Install the ALB controller

```bash
export VPC_ID=$(terraform -chdir=terraform output -raw vpc_id)
export LBC_ROLE_ARN=$(terraform -chdir=terraform output -raw load_balancer_controller_role_arn)
helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update eks
```

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --kube-context 8byte-eks \
  --namespace kube-system \
  --version 3.5.0 \
  --values helm/values/aws-load-balancer-controller.yaml \
  --set-string clusterName="$EKS_CLUSTER" \
  --set-string region="$AWS_REGION" \
  --set-string vpcId="$VPC_ID" \
  --set-string "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=$LBC_ROLE_ARN" \
  --atomic --wait --timeout 10m
```

## 7. Install Prometheus and Grafana

```bash
kubectl --context 8byte-eks create namespace monitoring --dry-run=client -o yaml | kubectl --context 8byte-eks apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community
```

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --kube-context 8byte-eks \
  --namespace monitoring \
  --version 88.6.3 \
  --values helm/values/monitoring.yaml \
  --atomic --wait --timeout 15m
```

## 8. Install the application chart

```bash
helm upgrade --install 8byte-app helm/8byte-app \
  --kube-context 8byte-eks \
  --namespace default \
  --set-string backend.image.repository="$BACKEND_ECR" \
  --set-string backend.image.tag="$IMAGE_TAG" \
  --set-string frontend.image.repository="$FRONTEND_ECR" \
  --set-string frontend.image.tag="$IMAGE_TAG" \
  --set-string database.host="$RDS_HOST" \
  --atomic --wait --timeout 5m
```

The application chart also runs PostgreSQL Exporter, with its password mounted from the existing Kubernetes Secret. The monitoring values create the Flask and PostgreSQL ServiceMonitors. No dashboard JSON is stored in the repository.

## 9. Access the application and Grafana

```bash
kubectl --context 8byte-eks -n default get ingress 8byte-app-ingress --watch
```

After the address appears, press `Control-C` and run:

```bash
export APP_HOST=$(kubectl --context 8byte-eks -n default get ingress 8byte-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$APP_HOST"
curl -i "http://$APP_HOST/health"
curl -i -X POST "http://$APP_HOST/api/visits"
```

Access Grafana privately:

```bash
kubectl --context 8byte-eks -n monitoring port-forward service/monitoring-grafana 3000:80
```

Open <http://localhost:3000>. Username: `admin`. Retrieve the generated password in another terminal:

```bash
kubectl --context 8byte-eks -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 --decode
```

Create dashboards manually in Grafana using the Prometheus data source.

Application dashboard queries:

```promql
sum(rate(flask_http_request_total[5m]))
```

```promql
100 * sum(rate(flask_http_request_total{status=~"5.."}[5m])) / clamp_min(sum(rate(flask_http_request_total[5m])), 1)
```

```promql
histogram_quantile(0.95, sum by (le) (rate(flask_http_request_duration_seconds_bucket[5m])))
```

PostgreSQL dashboard queries:

```promql
max(pg_up)
```

```promql
sum(pg_stat_database_numbackends{datname="appdb"})
```

```promql
max(pg_database_size_bytes{datname="appdb"})
```

```promql
sum(rate(pg_stat_database_xact_commit{datname="appdb"}[5m]))
```

The monitoring chart already includes standard Kubernetes/node dashboards for CPU, memory, and filesystem usage.

## CI/CD

The PR workflow runs unit/integration tests and `pip-audit`. The main workflow builds and scans images, authenticates to AWS with GitHub OIDC, deploys with the local application Helm chart, deploys staging, waits for production approval, and notifies on failure.

Configure GitHub variables `AWS_ACCOUNT_ID`, `RDS_HOST`, and `NOTIFY_EMAIL`. Configure `EMAIL_USERNAME` and `EMAIL_PASSWORD` as secrets when email notification is enabled. Add a required reviewer to the `production` GitHub Environment.

## Teardown

Delete Helm resources while the ALB controller is still available:

```bash
helm --kube-context 8byte-eks uninstall 8byte-app --namespace default --ignore-not-found
```

Wait until the application ALB disappears, then run:

```bash
helm --kube-context 8byte-eks uninstall monitoring --namespace monitoring --ignore-not-found
helm --kube-context 8byte-eks uninstall aws-load-balancer-controller --namespace kube-system --ignore-not-found
kubectl --context 8byte-eks -n default delete secret db-credentials --ignore-not-found
terraform -chdir=terraform plan -destroy -out=destroy.tfplan
terraform -chdir=terraform show -no-color destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
```

The S3 state bucket is retained because `prevent_destroy` protects it from accidental state loss.
