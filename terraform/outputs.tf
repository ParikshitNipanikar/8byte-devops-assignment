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

output "vpc_id" {
  value = aws_vpc.main.id
}