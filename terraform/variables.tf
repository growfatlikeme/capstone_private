variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}


variable "team_members" {
  type    = list(string)
}

variable "enable_external_dns" {
  type    = bool
  default = true
}

# variable "oidc_provider_url" {
#   description = "arn:aws:iam::255945442255:role/growfat_oidc"
#   type        = string
#   default = ""
# }