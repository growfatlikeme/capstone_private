resource "aws_s3_bucket" "logging_bucket" {
  bucket        = "${local.name_prefix}-logging"
  force_destroy = true
}
