# Challenges and Resolutions

## Migration to a new AWS account

- **Deleted source account:** The original Terraform state referenced resources in an AWS account that no longer existed. Reusing it would have produced misleading refresh failures and potentially unsafe replacement plans. The legacy local state was moved to ignored `.history/legacy-state-deleted-account/`, a new account-specific state bucket was bootstrapped, and the main stack was initialized against that clean backend.
- **Account safety:** The AWS provider and bootstrap configuration now require an explicit account ID through `allowed_account_ids`. A correct credential with the wrong account therefore fails before resource creation.
- **Old hardcoded identifiers:** The previous account ID, ECR URLs, RDS hostname, and public ALB URLs were embedded in workflow/manifests/docs. Image and database fields now use deployment placeholders; the workflow derives ECR URLs from `AWS_ACCOUNT_ID`.

## AWS Free Plan restrictions

- **EKS nodes rejected:** The first managed node group used `t3.medium`, which this account's Free Plan rejected as ineligible. AWS reported the restriction in Auto Scaling activity. The node group had no instances or data, so it was safely replaced with two eligible `m7i-flex.large` x86 nodes while remaining within the five-vCPU regional quota.
- **RDS backup retention rejected:** Seven-day retention was rejected by the account plan. The configurable retention was reduced to one day, and the documentation records this demo-account limitation.
- **Cost is not zero:** EKS, NAT Gateway, ALB, and observability consume Free Plan credits. Short log/metric retention and a single NAT Gateway constrain the demo cost; prompt teardown remains important.

## State and secrets

- **Deprecated state locking design:** The original instructions described a DynamoDB lock table. Terraform now uses S3 native lock files (`use_lockfile = true`) with bucket encryption, versioning, and public-access blocking.
- **Password in a local tfvars file:** A legacy database password was present in an ignored local file and appeared during validation. It was treated as compromised, quarantined with the legacy account files, and not reused. RDS now uses `manage_master_user_password`; AWS Secrets Manager owns the generated credential.
- **Safe Kubernetes transfer:** The database password is streamed from Secrets Manager into `kubectl create secret` and is neither printed nor written to a checked-in file.

## EKS and ingress

- **Load Balancer Controller IAM drift:** Manual `eksctl` commands and an older policy made the original installation difficult to reproduce. Terraform now owns the EKS OIDC provider, pinned official controller policy, IRSA role, and attachment. Helm receives the explicit VPC ID and service-account role.
- **Frontend target unhealthy:** A single ingress-level `/health` path applied to both target groups, but nginx serves its health response at `/`. Health-check annotations were moved to each Service: `/health` for Flask and `/` for nginx.
- **Slow failed-node-group deletion:** AWS held an empty failed node group in `DELETING` for about 15 minutes. The apply was kept attached and a read-only EKS check confirmed normal service-side cleanup before the replacement began.

## Monitoring and logging

- **ServiceMonitor not producing targets:** The backend Service needs both a named `http` port and the `app: backend` label selected by the ServiceMonitor. After applying those fields, Prometheus reported both replicas `up` with no scrape errors.
- **Grafana/Prometheus exposure:** Separate public ALBs made monitoring convenient but exposed administrative surfaces and added cost. The maintained setup leaves them internal and documents local port-forward access.
- **Dashboard simplicity:** Large dashboard JSON ConfigMaps made the repository difficult to explain. They were removed; the interview runbook records the PromQL queries for manually creating application and PostgreSQL dashboards. Production automation could export these dashboards or provision them through Grafana APIs.
- **CloudWatch permissions:** The node role requires `CloudWatchAgentServerPolicy`. Terraform attaches it and pins the observability add-on version, avoiding a manual post-install fix.

## CI/CD

- **Long-lived AWS keys:** Static GitHub secrets were replaced with a repository-restricted GitHub OIDC trust and a short-lived IAM role. The role can push only to the two application ECR repositories, describe this EKS cluster, and edit only the `default` Kubernetes namespace.
- **Over-broad manifest apply:** Applying an entire manifest directory mixed application and monitoring lifecycles. The repository now uses separate local Helm charts for the application and observability, and installs the controller, monitoring, and app releases in their correct namespaces.
- **Vulnerability gates:** Dependency scanning remains in the PR workflow. The deployment workflow now scans both locally built images with Trivy and blocks HIGH/CRITICAL findings before push.
- **Manual production approval:** The workflow uses GitHub Environments. A required reviewer must still be configured in the repository's `production` Environment settings because that policy is external to workflow YAML.
