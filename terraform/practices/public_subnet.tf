resource "aws_internet_gateway" "public_igw" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "Internet gateway"
  }

}

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
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






