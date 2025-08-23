terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"

    }
  }

  backend "s3" {
    bucket = "sctp-ce10-tfstate"
    key    = "growfat_test.tfstate"
    region = "ap-southeast-1"
  }
}