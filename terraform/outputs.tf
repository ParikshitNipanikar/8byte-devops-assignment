output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "frontend_ecr_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS hostname without the port"
  value       = aws_db_instance.main.address
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN containing the RDS-managed master credentials"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "eks_node_role_name" {
  value = aws_iam_role.eks_nodes.name
}

output "load_balancer_controller_role_arn" {
  description = "IRSA role to annotate on the AWS Load Balancer Controller service account"
  value       = aws_iam_role.load_balancer_controller.arn
}

output "eks_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "github_actions_role_arn" {
  description = "Role assumed by GitHub Actions through OIDC"
  value       = aws_iam_role.github_actions.arn
}
