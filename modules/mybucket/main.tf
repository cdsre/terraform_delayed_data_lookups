data "aws_caller_identity" "this" {}
data "aws_region" "this" {}

resource "aws_s3_bucket" "couchbase_backup" {
  bucket        = "test-${data.aws_caller_identity.this.account_id}-${data.aws_region.this.id}-couchbase-backups"
  force_destroy = false
}
