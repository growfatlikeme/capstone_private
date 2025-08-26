resource "aws_s3_bucket" "logging_bucket" {
  bucket        = "growfattest-logging"
  force_destroy = true
}
