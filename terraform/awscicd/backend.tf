
terraform {
  backend "s3" {
    bucket         = "infrasture-backend-test-o56jiz"
    key            = "terraform/codebuild/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-version-code-track"
    encrypt        = true
  }
}
