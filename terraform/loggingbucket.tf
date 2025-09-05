resource "aws_s3_bucket" "logging_bucket" {
  bucket        = "group3-sre-logging"
  force_destroy = true
}
