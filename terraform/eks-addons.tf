locals {
  container_insights_log_groups = toset([
    "application",
    "dataplane",
    "host",
    "performance"
  ])
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/8byte-eks/cluster"
  retention_in_days = var.cloudwatch_log_retention_days
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = local.container_insights_log_groups

  name              = "/aws/containerinsights/8byte-eks/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_days
}

resource "aws_iam_role_policy_attachment" "eks_nodes_cloudwatch" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = var.cloudwatch_observability_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_cloudwatch_log_group.container_insights,
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.eks_nodes_cloudwatch
  ]
}
