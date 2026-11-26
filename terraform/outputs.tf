output "application_url" {
  description = "Public HTTPS frontend address. Publish public/ after provisioning."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "website_bucket_name" {
  description = "Private S3 bucket for public/ assets."
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.app.id
}

output "cloudfront_plan_status" {
  description = "Confirm ACTIVE before relying on Free plan coverage."
  value       = aws_pricingplanmanager_subscription.site.status
}

output "github_actions_role_arn" {
  description = "Set the AWS_ROLE_ARN GitHub Actions secret to this value."
  value       = aws_iam_role.github_deploy.arn
}

output "github_actions_variables" {
  value = {
    AWS_REGION                 = var.aws_region
    WEBSITE_BUCKET             = aws_s3_bucket.site.id
    CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.app.id
    AWS_APPLICATION_URL        = "https://${aws_cloudfront_distribution.app.domain_name}"
  }
}
