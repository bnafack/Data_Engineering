terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.50"
    }

  }
  required_version = ">= 1.4.0"
}

provider "aws" {
  region = "eu-west-1"
}
########################
# S3 Bucket for Backend
########################

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}
resource "aws_s3_bucket" "statebackend" {
  bucket = "infrasture-backend-test-${random_string.suffix.result}" # CHANGE: Must be globally unique

  tags = {
    Name        = "Terraform State Bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.statebackend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.statebackend.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.statebackend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#################################
# DynamoDB Table for State Lock
#################################
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-version-code-track"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform Lock Table"
    Environment = "Dev"
  }
}
