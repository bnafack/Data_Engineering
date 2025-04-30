output "vpc_id" {
  description = "ID of AWS VPC"
  value       = aws_subnet.dev.*.id
}

output "subnet_id" {
  description = "ID of subnet"
  value       = aws_subnet.dev.*.id
}

output "instance_id" {
  description = "ID of the instances"
  value       = aws_instance.dev.*.id
}


output "public_ip" {
  description = "Public IP of AWS instances"
  value       = aws_instance.dev.*.public_ip
}
