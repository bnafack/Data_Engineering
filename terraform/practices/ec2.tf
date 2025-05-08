resource "random_id" "dev" {
  byte_length = 8

}

resource "aws_key_pair" "dev" {
  key_name   = random_id.dev.hex
  public_key = file(var.public_key)
}


resource "aws_instance" "dev" {
  ami                         = "ami-0ba9cfae65a212e98"
  instance_type               = "t2.nano"
  subnet_id                   = aws_subnet.vpc_subnet[0].id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.dev.key_name

  availability_zone = "eu-west-1b"

  ## Update your EC2 instance to use the new SG and detach the default one
  vpc_security_group_ids = [
    aws_security_group.sgr_vpc.id
  ]

  tags = {
    Name = "public_terraform1"
  }
}


resource "aws_security_group" "sgr_vpc" {
  vpc_id = aws_vpc.dev.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.subnets[1]]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  /*
  ingress {
    from_port       = 8
    to_port         = 0
    protocol        = "icmp"
    security_groups = [aws_security_group.sgr_vpc_private.id]
  }

  */
  tags = {
    Name = "Public_sg"
  }
}




/* resource "aws_network_interface_sg_attachment" "public" {
  security_group_id    = aws_security_group.sgr_vpc.id
  network_interface_id = aws_instance.dev.primary_network_interface_id
}

*/

