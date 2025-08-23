data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}


data "aws_route53_zone" "hosteddns" {
  name = "sctp-sandbox.com"
}
