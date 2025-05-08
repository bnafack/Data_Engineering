resource "aws_s3_bucket" "terraforms3bnaf" {
  bucket = "bnaf-test"

  tags = {
    Name        = "Terraform-test-bnaf"
    Environment = "ens"
  }
}


resource "aws_s3_bucket_public_access_block" "pb" {
  bucket                  = aws_s3_bucket.terraforms3bnaf.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}


resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.terraforms3bnaf.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "acl" {
  depends_on = [aws_s3_bucket_ownership_controls.ownership]
  bucket     = aws_s3_bucket.terraforms3bnaf.id
  acl        = "private"
}


resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.dev.id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = ["${aws_route_table.public_rtb.id}"]

  tags = {
    Name = "my-s3-endpoint"
  }
}
