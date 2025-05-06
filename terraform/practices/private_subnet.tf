resource "aws_instance" "private_ec2" {
  ami                         = "ami-0ba9cfae65a212e98"
  instance_type               = "t2.nano"
  subnet_id                   = aws_subnet.vpc_subnet[1].id
  associate_public_ip_address = false
  key_name                    = aws_key_pair.dev.key_name
  availability_zone           = "eu-west-1b"
  ## Update your EC2 instance to use the new SG and detach the default one
  vpc_security_group_ids = [
    aws_security_group.sgr_vpc_private.id
  ]



  tags = {
    Name = "private_terraform1"
  }
}


resource "aws_security_group" "sgr_vpc_private" {
  vpc_id = aws_vpc.dev.id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sgr_vpc.id]
  }

  ingress {
    from_port       = 8
    to_port         = 0
    protocol        = "icmp"
    security_groups = [aws_security_group.sgr_vpc.id] #If you're allowing SSH from a public instance to a private EC2
  }

  egress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sgr_vpc.id] #If you're allowing SSH from a public instance to a private EC2
  }

  # Egress: allow ICMP replies and general traffic back
  egress {
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.sgr_vpc.id] #If you're allowing SSH from a public instance to a private EC2
  }

  tags = {
    Name = "private_sg"
  }
}


resource "aws_route_table" "private_rtb" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "Private route"
  }
}


resource "aws_route_table_association" "rtb_connect" {
  subnet_id      = aws_subnet.vpc_subnet[1].id
  route_table_id = aws_route_table.private_rtb.id

}

/*

resource "aws_network_interface_sg_attachment" "private" {
  security_group_id    = aws_security_group.sgr_vpc_private.id
  network_interface_id = aws_instance.private_ec2.primary_network_interface_id
}

*/

