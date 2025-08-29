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