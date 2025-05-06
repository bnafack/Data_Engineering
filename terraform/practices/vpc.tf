resource "aws_vpc" "dev" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = var.vpc_name
  }

}

resource "aws_subnet" "vpc_subnet" {
  count             = length(var.subnets)
  vpc_id            = aws_vpc.dev.id
  cidr_block        = element(var.subnets, count.index)
  availability_zone = "eu-west-1b"
  tags = {
    Name = var.class_subnet[count.index]
  }

}


resource "aws_network_acl" "main" {

  vpc_id = aws_vpc.dev.id

  ingress {
    protocol   = "tcp"
    rule_no    = 2
    action     = "allow"
    cidr_block = var.subnets[0]
    from_port  = 22
    to_port    = 22
  }

  # Egress rules

  # Allow SSH return traffic (ephemeral ports)
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.subnets[0]
    from_port  = 1024
    to_port    = 65535
  }

  # Allow ICMP Echo Reply (type 0 = echo reply)
  egress {
    protocol   = "icmp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.subnets[0]
    from_port  = 0
    to_port    = 0
  }


  ingress {
    protocol   = "tcp"
    rule_no    = 4
    action     = "allow"
    cidr_block = var.subnets[0]
    from_port  = 80
    to_port    = 80
  }

  # Allow ICMP Echo Request (type 8 = echo request)

  ingress {
    protocol   = "icmp"
    rule_no    = 111
    action     = "allow"
    cidr_block = var.subnets[0]
    from_port  = 8
    to_port    = 0
  }


  tags = {
    Name = "test-terrafrom"
  }
}


resource "aws_network_acl_association" "main" {
  network_acl_id = aws_network_acl.main.id
  subnet_id      = aws_subnet.vpc_subnet[1].id
}

