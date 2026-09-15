# Implementation Approach

## Delivery strategy

The work follows a dependency-first sequence: establish trustworthy state, provision networking and managed services, connect the cluster, deploy internally, verify the database path, expose the application, then add monitoring and delivery automation. Each Terraform change is applied from a reviewed saved plan.

## Requirement mapping

| Assignment requirement | Implementation | Rationale |
|---|---|---|
| Public/private networking | Two public and two private subnets across two AZs | ALB remains public while compute and data remain private |
| Application hosting | EKS 1.36 with two managed x86 nodes | Demonstrates Kubernetes deployment, service discovery, ingress, and observability |
| PostgreSQL | Private RDS PostgreSQL 16 | Managed backups, metrics, patching, and Secrets Manager integration |
| Load balancing | Pinned AWS Load Balancer Controller chart plus application Helm Ingress template | Automatically reconciles target groups as Pods change while keeping configuration reproducible |
| State management | Encrypted/versioned S3 backend with native lock file | Shared, recoverable state without deprecated DynamoDB locking |
| Configurability/outputs | Variables for account, region, versions, node types, retention; outputs for operational IDs | Makes account migration and scripted setup predictable |
| PR validation | Pytest unit/integration suite and pip-audit | Exercises both HTTP behavior and a real PostgreSQL service |
| Build and deploy | GitHub Actions, immutable ECR SHA/attempt tags, local Helm chart, staging then gated production | Uses the same deployment package locally and in CI with an auditable approval point |
| Container scanning | Trivy HIGH/CRITICAL gate plus ECR scan-on-push | Fails before deployment and retains registry-side findings |
| Failure notification | SMTP action on failed test/deploy workflow | Meets notification requirement without embedding mail credentials |
| Infrastructure metrics | Prometheus node exporter and kube-state-metrics | Grafana provides Kubernetes CPU, memory, filesystem, Pod, and workload dashboards |
| Application metrics | Prometheus Flask exporter, ServiceMonitor, and documented manual Grafana queries | Tracks request rate, errors, and latency directly from the app |
| Database metrics | PostgreSQL Exporter, ServiceMonitor, and documented manual Grafana queries | Tracks availability, connections, size, locks, commits, and rollbacks in the same monitoring interface |
| Centralized logging | CloudWatch Observability add-on and seven-day log groups | Collects application, host, dataplane, performance, and control-plane logs |
| Secret management | RDS-managed Secrets Manager secret and Kubernetes Secret | No database password in Terraform variables, Git, or CI output |
| Backup strategy | RDS automated backups | Managed point-in-time recovery within the Free Plan retention constraint |

## Security model

Trust boundaries are explicit: internet traffic terminates at the ALB; application Pods are the only database clients; the controller uses IRSA; GitHub uses OIDC; and monitoring has no public endpoint. Account-ID guards reduce operator error, while remote state controls and short retention limit accidental exposure and cost.

## Tradeoffs

- One NAT Gateway lowers demo cost but is an AZ-level egress dependency.
- Staging and production GitHub Environments currently deploy to the same demonstration namespace. Separate accounts/clusters/namespaces would be preferable for real production isolation.
- HTTP is acceptable for assignment verification only. Production should use Route 53, ACM, HTTPS redirect, WAF, and a restricted origin policy.
- One-day RDS retention is an account-plan restriction, not the recommended production setting.

## Next production improvements

1. Separate staging and production AWS accounts and Terraform state.
2. Use External Secrets Operator or Secrets Store CSI for continuous secret synchronization and rotation.
3. Add ACM TLS, Route 53, WAF, HPA, PodDisruptionBudgets, NetworkPolicies, and restrictive pod security contexts.
4. Add alert routing to Slack/PagerDuty and SLO-based alerts for availability and latency.
5. Add multi-AZ NAT/RDS, deletion protection, final snapshots, longer backup retention, and restore testing.
6. Pin GitHub Actions by commit SHA and generate an SBOM with signed container attestations.
