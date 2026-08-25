###############################################################################
# RDS PostgreSQL — metadata store (no misconfiguration)
###############################################################################

resource "aws_db_subnet_group" "this" {
  name       = "sec-lab-db-subnet-group-prod"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "sec-lab-db-subnet-group-prod" }
}

resource "aws_db_instance" "this" {
  identifier     = "sec-lab-db-prod"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "tenantdb"
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]

  publicly_accessible = false
  multi_az            = false
  skip_final_snapshot = true

  tags = { Name = "sec-lab-db-prod" }
}
