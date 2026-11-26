data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront-scoped WAF resources must be created in us-east-1.
resource "aws_wafv2_web_acl" "site" {
  provider = aws.us_east_1
  name     = "${var.project_name}-static"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${var.project_name}-static"
    sampled_requests_enabled   = false
  }
}

# Keep this address so an existing distribution can switch origins in place.
resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name} static frontend"
  web_acl_id          = aws_wafv2_web_acl.site.arn

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "static-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "static-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# A Free subscription requires both the distribution and its dedicated web ACL.
# No configurable paid tier or automatic paid fallback.
resource "aws_pricingplanmanager_subscription" "site" {
  plan_family = "CloudFront"
  plan_tier   = "FREE"
  usage_level = "DEFAULT"
  resource_arns = [
    aws_cloudfront_distribution.app.arn,
    aws_wafv2_web_acl.site.arn,
  ]
}
