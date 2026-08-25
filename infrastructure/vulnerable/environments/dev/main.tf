###############################################################################
# CI/CD Pipeline IAM User (static credentials — intentional misconfiguration)
###############################################################################

module "iam_pipeline_user" {
  source = "../../modules/iam_pipeline_user"

  prod_account_id = var.prod_account_id
}
