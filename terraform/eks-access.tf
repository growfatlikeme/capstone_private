locals {
  team_member_arns = toset([
    format("arn:aws:iam::%s:user/%s", var.aws_account_id, var.mem1),
    format("arn:aws:iam::%s:user/%s", var.aws_account_id, var.mem2),
    format("arn:aws:iam::%s:user/%s", var.aws_account_id, var.mem3),
    format("arn:aws:iam::%s:user/%s", var.aws_account_id, var.mem4),
    format("arn:aws:iam::%s:user/%s", var.aws_account_id, var.mem5),
  ])
}

# Grant cluster admin access to team members
resource "aws_eks_access_entry" "team_members" {
  for_each      = local.team_member_arns
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}


# Use policy association for admin permissions
resource "aws_eks_access_policy_association" "team_admin_policy" {
  for_each      = local.team_member_arns
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.team_members]
}