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

# role for ExternalDNS
module "external_dns_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "~> 5.52.1"

  count = var.enable_external_dns ? 1 : 0

  create_role                    = true
  role_name                      = "${local.name_prefix}-externaldns-oidc-role"
  provider_url                   = module.eks.oidc_provider
  oidc_fully_qualified_audiences = ["sts.amazonaws.com"]

  provider_trust_policy_conditions = [
    {
      test     = "StringLike"
      values   = ["system:serviceaccount:*:external-dns"]
      variable = "${module.eks.oidc_provider}:sub"
    }
  ]

  inline_policy_statements = [
    {
      actions = [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ]
      effect    = "Allow"
      resources = ["*"]
    },
    {
      actions = [
        "route53:ChangeResourceRecordSets"
      ]
      effect    = "Allow"
      resources = ["arn:aws:route53:::hostedzone/*"]
    }
  ]
}
