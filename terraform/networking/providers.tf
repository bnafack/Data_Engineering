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
