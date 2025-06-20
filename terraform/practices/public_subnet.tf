resource "aws_internet_gateway" "public_igw" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "Internet gateway"
  }

}

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = var.public_cidr
    gateway_id = aws_internet_gateway.public_igw.id
  }

  tags = {
    Name = "Public route"
  }
}


resource "aws_route_table_association" "rtb_igw" {
  subnet_id      = aws_subnet.vpc_subnet[0].id
  route_table_id = aws_route_table.public_rtb.id

}

resource "aws_network_acl" "public_nacls" {

  vpc_id = aws_vpc.dev.id

  ingress {
    protocol   = "tcp"
    rule_no    = 2
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 22
    to_port    = 22
  }


  egress {
    protocol   = "tcp"
    rule_no    = 2
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }
  # Egress rules

  # Allow return traffic (ephemeral + ICMP reply)
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 1024
    to_port    = 65535
  }

  # Allow return traffic (ephemeral + ICMP reply)
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 1024
    to_port    = 65535
  }


  # Allow ICMP Echo Reply (type 0 = echo reply)
  egress {
    protocol   = "icmp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "icmp"
    rule_no    = 121
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 8
    to_port    = 0
  }

  egress {
    protocol   = "tcp"
    rule_no    = 4
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 80
    to_port    = 80
  }



  egress {
    protocol   = "tcp"
    rule_no    = 5
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 443
    to_port    = 443
  }


  # Allow ICMP Echo Request (type 8 = echo request)

  ingress {
    protocol   = "icmp"
    rule_no    = 111
    action     = "allow"
    cidr_block = var.public_cidr
    from_port  = 8
    to_port    = 0
  }


  tags = {
    Name = "nacl_public_subnet"
  }
}



resource "aws_network_acl_association" "public_subnet" {
  network_acl_id = aws_network_acl.public_nacls.id
  subnet_id      = aws_subnet.vpc_subnet[0].id
}



