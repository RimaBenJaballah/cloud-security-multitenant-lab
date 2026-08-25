output "phase2_note" {
  description = "Phase 2 CI/CD identity model"
  value       = "No IAM pipeline user is created. GitHub Actions uses OIDC to assume the prod Deploy Role."
}
