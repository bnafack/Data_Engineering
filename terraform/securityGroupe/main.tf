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

/*
resource "aws_instance" "lesson_04" {
  ami           = "ami-0ba9cfae65a212e98"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.sg_ssh.id,
    aws_security_group.sg_https.id

  ]

  tags = {
    Name = "Lesson-04-aws-instance"
  }

}
*/
resource "aws_security_group" "sg_ssh" {
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }

}

resource "aws_security_group" "sg_https" {
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }

}
