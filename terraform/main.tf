locals {
  name_prefix = "group3-SRE"
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  bootstrap_self_managed_addons = true

  cluster_name    = "${local.name_prefix}-cluster"
  cluster_version = "1.33"

#ensure coreDNS is created in different zone upon startup, to maintain HA incase 1 zone goes down.
  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [{
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [{
                    key      = "k8s-app"
                    operator = "In"
                    values   = ["kube-dns"]
                  }]
                }
                topologyKey = "topology.kubernetes.io/zone"
              }
            }]
          }
        }
      })
    }
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    group3_ng = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      min_size       = 3
      max_size       = 5
      desired_size   = 4
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8.1"

  name                    = "${local.name_prefix}_vpc"
  cidr                    = "172.31.0.0/16"
  azs                     = data.aws_availability_zones.available.names
  public_subnets          = ["172.31.101.0/24", "172.31.102.0/24", "172.31.103.0/24"]
  private_subnets         = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
  enable_nat_gateway      = true
  single_nat_gateway      = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
  
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.34.0"

  cluster_name                    = module.eks.cluster_name
  enable_pod_identity             = true
  create_pod_identity_association = true
  namespace                       = "kube-system"
  iam_role_name                   = "${local.name_prefix}-karpenter_controller"
  iam_role_use_name_prefix        = false
  iam_policy_name                 = "${local.name_prefix}-KarpenterControllerPolicy"
  iam_policy_use_name_prefix      = false
  iam_policy_description          = "Karpenter controller policy with all necessary permissions"
  node_iam_role_name              = "${local.name_prefix}-KarpenterNodeRole"
  node_iam_role_use_name_prefix   = false
  node_iam_role_description       = "Karpenter node role with all necessary permissions"
  queue_name                      = module.eks.cluster_name
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }
}
