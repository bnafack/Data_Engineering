
terraform {
  backend "s3" {
    bucket         = "infrasture-backend-test-o56jiz"
    key            = "terraform/codepipeline/terraform.tfstate"
    region         = "eu-west-1"
    use_lockfile   = true
    encrypt        = true
  }
}
