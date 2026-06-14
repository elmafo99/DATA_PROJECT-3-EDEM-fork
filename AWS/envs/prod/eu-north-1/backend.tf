# State backend (S3 + DynamoDB lock). Mirrors GCP's GCS backend pattern, but
# the bucket/table cannot be created by this stack itself (chicken-and-egg) —
# bootstrap once manually before the first `terraform init`:
#
#   aws s3api create-bucket --bucket store-tfstate-eu-north-1 \
#     --region eu-north-1 \
#     --create-bucket-configuration LocationConstraint=eu-north-1
#   aws s3api put-bucket-versioning --bucket store-tfstate-eu-north-1 \
#     --versioning-configuration Status=Enabled
#   aws dynamodb create-table --table-name store-tfstate-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region eu-north-1

terraform {
  backend "s3" {
    bucket         = "store-tfstate-eu-north-1"
    key            = "aws-prod/eu-north-1/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "store-tfstate-lock"
    encrypt        = true
  }
}
