output "vpc_id" {
  value       = aws_vpc.main-vpc.id
  description = "VPC ID"
}
output "public_subnet_ids" {
  description = "IDs of the created public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the created private subnets"
  value       = aws_subnet.private[*].id
}
