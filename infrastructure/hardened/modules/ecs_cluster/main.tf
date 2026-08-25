resource "aws_ecs_cluster" "this" {
  name = "sec-lab-cluster-prod"

  tags = { Name = "sec-lab-cluster-prod" }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/sec-lab-api"
  retention_in_days = 7

  tags = { Name = "/ecs/sec-lab-api" }
}
