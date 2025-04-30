resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.dev.id
  tags = {
    Name = "inetrnet gateway"
  }

}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public.id
  }

  tags = {
    Name = "Public Route table"
  }
}


resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.dev[0].id
  route_table_id = aws_route_table.public.id

}
