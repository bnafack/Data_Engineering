output "vpc_id" {
  description = "ID of AWS VPC"
  value       = aws_vpc.dev.id
}

output "subnet_id" {
  description = "ID of subnet"
  value       = aws_subnet.vpc_subnet[1].id
}

output "instance_id" {
  description = "ID of the instances"
  value       = aws_instance.dev.id
}


output "public_ip" {
  description = "Public IP of AWS instances"
  value       = aws_instance.dev.public_ip
}


output "instance_id_private" {
  description = "ID of the instances"
  value       = aws_instance.private_ec2.id
}
output "private_ip" {
  description = "Public IP of AWS instances"
  value       = aws_instance.private_ec2.private_ip
}
