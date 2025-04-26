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

resource "aws_vpc" "terraform_test" {
  cidr_block = "10.2.0.0/16"

  tags = {
    Name = "Terraform"
  }
}

resource "aws_subnet" "Public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.terraform_test.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)
  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "Private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.terraform_test.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)


  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }

}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.terraform_test.id

  tags = {
    Name = "Project VPC IG"
  }

}

resource "aws_route_table" "second_rt" {
  vpc_id = aws_vpc.terraform_test.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "2nd route Table"
  }
}


resource "aws_route_table_association" "public_subnet_asso" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.Public_subnets[*].id, count.index)
  route_table_id = aws_route_table.second_rt.id
}


resource "aws_instance" "lesson_03" {
  ami           = "ami-0ba9cfae65a212e98"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.Public_subnets[1].id

  tags = {
    Name = "Lesson-03-aws-instance"
  }
}

output "PublicIP" {
  value = aws_instance.lesson_03.public_ip
}
