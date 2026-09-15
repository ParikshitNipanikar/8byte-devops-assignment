# Helm layout

Run the Helm commands from the repository root after Terraform and the image push are complete. The full commands and required Terraform output variables are documented in the root `README.md`.

There are three releases rather than one umbrella release because each component has a different namespace and lifecycle:

| Release | Namespace | Configuration |
|---|---|---|
| AWS Load Balancer Controller | `kube-system` | `values/aws-load-balancer-controller.yaml` |
| Prometheus and Grafana | `monitoring` | `values/monitoring.yaml` |
| Application and PostgreSQL Exporter | `default` | `8byte-app/` local chart |

Keeping separate releases avoids placing application Pods or monitoring components in `kube-system`.

The database password is intentionally not included in Helm values. Helm stores release values in the cluster, so stream the password directly from Secrets Manager into a Kubernetes Secret before installing the application.

The monitoring values create the Flask and PostgreSQL ServiceMonitors. Grafana dashboards are created manually from the PromQL queries documented in the root README and interview runbook; no large dashboard JSON files are kept in the chart.
