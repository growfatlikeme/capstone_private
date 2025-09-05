variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}


variable "team_members" {
  type    = list(string)
}


# variable "oidc_provider_url" {
#   description = "arn:aws:iam::xxxxxxx:role/xxxxxx"
#   type        = string
#   default = ""
# }