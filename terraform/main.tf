locals {
  name_prefix = "growfattest"
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
    learner_ng = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      min_size       = 3
      max_size       = 3
      desired_size   = 3
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
  database_subnets        = ["172.31.51.0/24", "172.31.52.0/24", "172.31.53.0/24"]
  enable_nat_gateway      = true
  single_nat_gateway      = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
  database_subnet_tags = {
    "kubernetes.io/role/database" = 1
  }  
  
}