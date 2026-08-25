###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "sec-lab-vpc-prod" }
}

###############################################################################
# Subnets
###############################################################################

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = { Name = "sec-lab-public-a-prod" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = { Name = "sec-lab-public-b-prod" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.region}a"

  tags = { Name = "sec-lab-private-a-prod" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "${var.region}b"

  tags = { Name = "sec-lab-private-b-prod" }
}

###############################################################################
# Internet Gateway
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "sec-lab-igw-prod" }
}

###############################################################################
# NAT Gateway (single AZ — eu-west-3a)
###############################################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "sec-lab-nat-eip-prod" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = { Name = "sec-lab-nat-prod" }

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Route Tables
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "sec-lab-rt-public-prod" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "sec-lab-rt-private-prod" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# Security Groups
###############################################################################

# --- ALB SG ---
resource "aws_security_group" "alb" {
  name        = "sec-lab-alb-sg-prod"
  description = "ALB security group"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sec-lab-alb-sg-prod" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_in" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# --- ECS SG ---
# MISCONFIGURATION: outbound all traffic to 0.0.0.0/0
# Intended: TCP 443 to 0.0.0.0/0 + TCP 5432 to RDS SG only
resource "aws_security_group" "ecs" {
  name        = "sec-lab-ecs-sg-prod"
  description = "ECS security group - MISCONFIGURED: open egress"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sec-lab-ecs-sg-prod" }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# MISCONFIGURATION — open egress enables Path 1 OOB credential exfiltration
resource "aws_vpc_security_group_egress_rule" "ecs_all_out" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- RDS SG ---
resource "aws_security_group" "rds" {
  name        = "sec-lab-rds-sg-prod"
  description = "RDS security group"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sec-lab-rds-sg-prod" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
