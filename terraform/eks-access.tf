# Grant cluster admin access to team members
resource "aws_eks_access_entry" "team_members" {
  for_each = toset([
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem1}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem2}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem3}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem4}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem5}",
  ])

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type         = "STANDARD"
}

# Use policy association for admin permissions
resource "aws_eks_access_policy_association" "team_admin_policy" {
  for_each = toset([
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem1}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem2}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem3}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem4}",
    "arn:aws:iam::${var.aws_account_id}:user/${var.mem5}",
  ])

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.team_members]
}