variable "aws_account_id" {
  description = "AWS account that Terraform is allowed to modify"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources are created"
  type        = string
  default     = "ap-south-1"
}

variable "eks_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.36"
}

variable "cloudwatch_observability_addon_version" {
  description = "Pinned amazon-cloudwatch-observability add-on version compatible with the EKS version"
  type        = string
  default     = "v6.6.0-eksbuild.1"
}

variable "cloudwatch_log_retention_days" {
  description = "Retention period for EKS and Container Insights log groups"
  type        = number
  default     = 7
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "rds_backup_retention_days" {
  description = "Automated RDS backup retention; the AWS Free account plan currently permits one day"
  type        = number
  default     = 1

  validation {
    condition     = var.rds_backup_retention_days >= 0 && var.rds_backup_retention_days <= 35
    error_message = "rds_backup_retention_days must be between 0 and 35."
  }
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to assume the CI/CD role"
  type        = string
  default     = "ParikshitNipanikar/8byte-devops-assignment"
}
