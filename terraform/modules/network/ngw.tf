# resource "aws_eip" "lb" {
#   domain   = "vpc"
# }
# resource "aws_nat_gateway" "ngw" {
#   allocation_id = aws_eip.lb.id
#   subnet_id     = aws_subnet.public_subnet_1.id
#   tags = {
#     Name = var.ngw_tagname
#   }
#   depends_on = [aws_internet_gateway.igw]
# }
