mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_cloudfront_cache_policy" {
    defaults = { id = "658327ea-f89d-4fab-a63d-7e88639e58f6" }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                         = "arn:aws:s3:::feedback-test"
      bucket_regional_domain_name = "feedback-test.s3.eu-west-2.amazonaws.com"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/EXAMPLE"
      id          = "EXAMPLE"
      domain_name = "example.cloudfront.net"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/feedback-test/12345678-1234-1234-1234-123456789012"
    }
  }
}

variables {
  github_repository     = "example/feedback-portal"
  github_branch         = "develop"
  github_repository_ids = null
}

run "private_static_hosting_with_free_plan" {
  command = apply

  assert {
    condition = (
      aws_s3_bucket_public_access_block.site.block_public_acls &&
      aws_s3_bucket_public_access_block.site.block_public_policy &&
      aws_s3_bucket_public_access_block.site.ignore_public_acls &&
      aws_s3_bucket_public_access_block.site.restrict_public_buckets &&
      one(aws_s3_bucket_ownership_controls.site.rule).object_ownership == "BucketOwnerEnforced"
    )
    error_message = "The website bucket must remain private with ACLs disabled."
  }

  assert {
    condition = (
      aws_pricingplanmanager_subscription.site.plan_tier == "FREE" &&
      aws_pricingplanmanager_subscription.site.plan_family == "CloudFront" &&
      aws_pricingplanmanager_subscription.site.resource_arns == toset([
        aws_cloudfront_distribution.app.arn,
        aws_wafv2_web_acl.site.arn,
      ])
    )
    error_message = "Free coverage must include the distribution and its dedicated WAF ACL."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.app.default_root_object == "index.html" &&
      one(aws_cloudfront_distribution.app.origin).origin_access_control_id == aws_cloudfront_origin_access_control.site.id &&
      one(aws_cloudfront_distribution.app.default_cache_behavior).viewer_protocol_policy == "redirect-to-https" &&
      one(aws_cloudfront_distribution.app.default_cache_behavior).allowed_methods == toset(["GET", "HEAD"])
    )
    error_message = "CloudFront must serve index.html over HTTPS through a signed S3 origin."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Principal.Service == "cloudfront.amazonaws.com" &&
      jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == aws_cloudfront_distribution.app.arn
    )
    error_message = "Only this CloudFront distribution may read website objects."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.github_deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example/feedback-portal:ref:refs/heads/develop" &&
      length(jsondecode(aws_iam_role_policy.github_deploy.policy).Statement) == 3 &&
      jsondecode(aws_iam_role_policy.github_deploy.policy).Statement[1].Resource == "${aws_s3_bucket.site.arn}/*" &&
      jsondecode(aws_iam_role_policy.github_deploy.policy).Statement[2].Resource == aws_cloudfront_distribution.app.arn
    )
    error_message = "Deployments must be branch-restricted and limited to this bucket and distribution."
  }
}

run "immutable_github_subject" {
  command = apply

  variables {
    github_repository_ids = {
      owner_id      = "123"
      repository_id = "456"
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.github_deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example@123/feedback-portal@456:ref:refs/heads/develop"
    error_message = "Immutable OIDC subjects must include the owner and repository IDs."
  }
}
