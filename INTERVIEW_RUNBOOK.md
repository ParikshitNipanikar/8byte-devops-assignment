# Interview Runbook — Direct Commands

This guide deliberately uses Terraform, Docker, kubectl, and Helm directly. No Makefile or wrapper script is involved.

The environment is currently destroyed. Allow approximately 20–35 minutes for AWS infrastructure and another 10–20 minutes for images, Helm releases, and the ALB.

## 1. Open the project and verify identity

```bash
cd /Users/parikshitnipanikar/8byte-devops-assignment
export AWS_REGION=ap-south-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws sts get-caller-identity
echo "$ACCOUNT_ID"
```

**Reason:** Confirm that every following command targets AWS account `385904685559` in Mumbai.

## 2. Create the Terraform state configuration

```bash
cp terraform-bootstrap/terraform.tfvars.example terraform-bootstrap/terraform.tfvars
sed -i '' "s/REPLACE_WITH_AWS_ACCOUNT_ID/$ACCOUNT_ID/" terraform-bootstrap/terraform.tfvars
```

**Reason:** Terraform requires the intended account explicitly. The provider refuses to modify a different account.

## 3. Create the remote-state bucket

```bash
terraform -chdir=terraform-bootstrap init
terraform -chdir=terraform-bootstrap fmt -check
terraform -chdir=terraform-bootstrap validate
terraform -chdir=terraform-bootstrap plan -out=bootstrap.tfplan
terraform -chdir=terraform-bootstrap show -no-color bootstrap.tfplan
terraform -chdir=terraform-bootstrap apply bootstrap.tfplan
```

**Reason:** The bootstrap creates the encrypted, private, versioned S3 bucket before the main configuration tries to use it. Terraform native S3 locking prevents concurrent state modification.

## 4. Create the main Terraform configuration

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
sed -i '' "s/REPLACE_WITH_AWS_ACCOUNT_ID/$ACCOUNT_ID/" terraform/terraform.tfvars
sed -i '' "s|YOUR_GITHUB_USERNAME@YOUR_GITHUB_OWNER_ID/8byte-devops-assignment@YOUR_REPOSITORY_ID|ParikshitNipanikar@111178325/8byte-devops-assignment@1350420946|" terraform/terraform.tfvars
```

**Reason:** This ignored file contains the current AWS account, region, and GitHub repository trust restriction. The non-secret S3 backend location is declared directly in `backend.tf` for this single-account assignment.

## 5. Provision AWS

```bash
terraform -chdir=terraform init -reconfigure
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=infra.tfplan
terraform -chdir=terraform show -no-color infra.tfplan
terraform -chdir=terraform apply infra.tfplan
terraform -chdir=terraform output
```

**Reason:** A saved plan guarantees that apply uses the exact reviewed VPC, EKS, RDS, ECR, IAM, and centralized logging changes.

**Say:** “The ALB is public. EKS workers, Pods, and RDS remain private. One NAT Gateway is a deliberate demo cost tradeoff.”

## 6. Connect kubectl to EKS

```bash
export EKS_CLUSTER=$(terraform -chdir=terraform output -raw eks_cluster_name)
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION" --alias 8byte-eks
kubectl --context 8byte-eks get nodes -o wide
```

**Expected:** Two worker nodes become `Ready`.

## 7. Read Terraform outputs

```bash
export VPC_ID=$(terraform -chdir=terraform output -raw vpc_id)
export LBC_ROLE_ARN=$(terraform -chdir=terraform output -raw load_balancer_controller_role_arn)
export BACKEND_ECR=$(terraform -chdir=terraform output -raw ecr_repository_url)
export FRONTEND_ECR=$(terraform -chdir=terraform output -raw frontend_ecr_repository_url)
export RDS_HOST=$(terraform -chdir=terraform output -raw rds_address)
export RDS_SECRET_ARN=$(terraform -chdir=terraform output -raw rds_master_secret_arn)
export IMAGE_TAG="$(git rev-parse --short=12 HEAD)-$(date -u +%Y%m%d%H%M%S)"
```

**Reason:** Terraform remains the source of truth. Nothing AWS-specific is copied manually into Helm templates.

## 8. Build and scan the images

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
docker build --pull --platform linux/amd64 -t "$BACKEND_ECR:$IMAGE_TAG" app/backend
docker build --pull --platform linux/amd64 -t "$FRONTEND_ECR:$IMAGE_TAG" app/frontend
trivy image --exit-code 1 --severity HIGH,CRITICAL "$BACKEND_ECR:$IMAGE_TAG"
trivy image --exit-code 1 --severity HIGH,CRITICAL "$FRONTEND_ECR:$IMAGE_TAG"
```

**Reason:** `linux/amd64` matches the EKS nodes even though the Mac is ARM64. Trivy blocks high and critical vulnerabilities before publishing.

## 9. Push immutable images to ECR

```bash
docker push "$BACKEND_ECR:$IMAGE_TAG"
docker push "$FRONTEND_ECR:$IMAGE_TAG"
```

**Reason:** The Git SHA plus timestamp makes the release traceable and prevents an immutable-tag collision during a repeated demo.

## 10. Create the Kubernetes database Secret

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

**Reason:** The password moves from Secrets Manager to Kubernetes without being printed, written into Helm values, or committed to Git.

## 11. Install the AWS Load Balancer Controller

```bash
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

**Reason:** The controller creates the AWS ALB from the application Ingress. IRSA supplies short-lived AWS permissions without static credentials.

## 12. Install Prometheus and Grafana

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

**Reason:** The pinned chart installs Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, and standard Kubernetes dashboards.

## 13. Install the application

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

**Reason:** One local chart owns the frontend, backend, PostgreSQL Exporter, Services, probes, and Ingress. The same chart is used by GitHub Actions. The exporter password is mounted from the existing Secret rather than stored in Helm values.

The monitoring values create ServiceMonitors for Flask and PostgreSQL Exporter. Dashboard panels will be created manually in Grafana, so there is no large dashboard JSON in the repository.

## 14. Verify everything

```bash
kubectl --context 8byte-eks get nodes
kubectl --context 8byte-eks get pods,services,ingress -A
helm --kube-context 8byte-eks list -A
```

**Expected:** Two ready nodes, healthy application/monitoring Pods, and three Helm releases.

## 15. Get and test the URL

```bash
kubectl --context 8byte-eks -n default get ingress 8byte-app-ingress --watch
```

After the address appears, press `Control-C`:

```bash
export APP_HOST=$(kubectl --context 8byte-eks -n default get ingress 8byte-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$APP_HOST"
curl -i "http://$APP_HOST/"
curl -i "http://$APP_HOST/health"
curl -i -X POST "http://$APP_HOST/api/visits"
curl -i -X POST "http://$APP_HOST/api/visits"
```

**Expected:** Frontend and health return HTTP 200. The second visit count is higher, proving the private RDS write/read path.

## 16. Access Grafana and create dashboards

```bash
kubectl --context 8byte-eks -n monitoring port-forward service/monitoring-grafana 3000:80
```

Open <http://localhost:3000>. Username: `admin`. Retrieve the password in a private second terminal:

```bash
kubectl --context 8byte-eks -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 --decode
```

In Grafana, select **Dashboards → New → New dashboard → Add visualization**, then choose the Prometheus data source.

Create an `8Byte Application RED Metrics` dashboard with these queries:

```promql
sum(rate(flask_http_request_total[5m]))
```

```promql
100 * sum(rate(flask_http_request_total{status=~"5.."}[5m])) / clamp_min(sum(rate(flask_http_request_total[5m])), 1)
```

```promql
histogram_quantile(0.95, sum by (le) (rate(flask_http_request_duration_seconds_bucket[5m])))
```

Create an `8Byte PostgreSQL Metrics` dashboard with these queries:

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
sum(pg_locks_count{datname="appdb"})
```

```promql
sum(rate(pg_stat_database_xact_commit{datname="appdb"}[5m]))
```

Also show the standard Kubernetes CPU, memory, and filesystem dashboards installed by the monitoring chart.

## 17. Show centralized CloudWatch logs

```bash
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/8byte-eks --region "$AWS_REGION"
aws logs describe-log-groups --log-group-name-prefix /aws/eks/8byte-eks --region "$AWS_REGION"
```

**Reason:** Prometheus and Grafana own all dashboards. CloudWatch remains focused on centralized application, host, dataplane, performance, and EKS control-plane logging.

## 18. Teardown after the interview

Confirm the account again:

```bash
aws sts get-caller-identity
```

Delete the Ingress while its controller is still running:

```bash
helm --kube-context 8byte-eks uninstall 8byte-app --namespace default --ignore-not-found
```

Wait until the AWS ALB disappears. Then remove the remaining releases:

```bash
helm --kube-context 8byte-eks uninstall monitoring --namespace monitoring --ignore-not-found
helm --kube-context 8byte-eks uninstall aws-load-balancer-controller --namespace kube-system --ignore-not-found
kubectl --context 8byte-eks -n default delete secret db-credentials --ignore-not-found
```

Review and apply the Terraform destroy plan:

```bash
terraform -chdir=terraform plan -destroy -out=destroy.tfplan
terraform -chdir=terraform show -no-color destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
```

**Reason:** ECR uses `force_delete`, so images do not need manual cleanup. The protected S3 state bucket remains as versioned recovery history.
