output "application_name" {
  description = "Elastic Beanstalk application name."
  value       = aws_elastic_beanstalk_application.app.name
}

output "environment_name" {
  description = "Elastic Beanstalk environment name."
  value       = aws_elastic_beanstalk_environment.app.name
}

output "application_url" {
  description = "Public HTTPS URL using CloudFront's included hostname and certificate."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution serving the public HTTPS endpoint."
  value       = aws_cloudfront_distribution.app.id
}

output "beanstalk_origin_url" {
  description = "HTTP origin for CloudFront; use application_url for browser access."
  value       = "http://${aws_elastic_beanstalk_environment.app.cname}"
}

output "artifact_bucket_name" {
  description = "Private S3 bucket used for application deployment bundles."
  value       = aws_s3_bucket.artifacts.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN to configure as the AWS_ROLE_ARN GitHub Actions secret."
  value       = aws_iam_role.github_deploy.arn
}

output "feedback_topic_arn" {
  description = "Existing SNS topic receiving submitted feedback."
  value       = var.sns_topic_arn
}
