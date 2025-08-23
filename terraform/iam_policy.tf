resource "aws_iam_policy" "external_dns" {
  name_prefix = "${local.name_prefix}-external-dns-"
  description = "External DNS policy for Route53 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          data.aws_route53_zone.hosteddns.arn,
          "arn:aws:route53:::hostedzone/g3-snakegame"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}


# Attach ELB policy to node group for LoadBalancer creation
resource "aws_iam_role_policy_attachment" "node_group_elb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = module.eks.eks_managed_node_groups.learner_ng.iam_role_name
}

resource "aws_iam_role" "github_oidc" {
  name = "github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::255945442255:oidc-provider/token.actions.githubusercontent.com"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          },
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:growfatlikeme/group3-sre:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_oidc_policy_attach" {
  role       = aws_iam_role.github_oidc.name
  policy_arn = aws_iam_policy.external_dns.arn
}