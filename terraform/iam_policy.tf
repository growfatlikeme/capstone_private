# Attach ELB policy to node group for LoadBalancer creation
resource "aws_iam_role_policy_attachment" "node_group_elb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = module.eks.eks_managed_node_groups.group3_ng.iam_role_name
}



resource "aws_iam_instance_profile" "karpenter" {
  name = "${local.name_prefix}-KarpenterNodeInstanceProfile"
  role = module.eks.eks_managed_node_groups.group3_ng.iam_role_name
}