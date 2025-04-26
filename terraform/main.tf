terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">=1.2.0"
}

provider "aws" {
  region = "eu-west-1"
}

resource "aws_instance" "lesson_03" {
  ami           = "ami-0ba9cfae65a212e98"
  instance_type = "t2.micro"

  tags = {
    Name = "Lesson-03-aws-instance"
  }
}
