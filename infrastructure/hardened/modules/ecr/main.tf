resource "aws_ecr_repository" "this" {
  name                 = "sec-lab-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
