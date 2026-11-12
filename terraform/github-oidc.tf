locals {
  github_repository_parts = split("/", var.github_repository)
  github_oidc_repository = var.github_repository_ids == null ? var.github_repository : format(
    "%s@%s/%s@%s",
    local.github_repository_parts[0], var.github_repository_ids.owner_id,
    local.github_repository_parts[1], var.github_repository_ids.repository_id,
  )
  beanstalk_storage_arn = "arn:${data.aws_partition.current.partition}:s3:::elasticbeanstalk-${var.aws_region}-${data.aws_caller_identity.current.account_id}"
  beanstalk_stack_arn   = "arn:${data.aws_partition.current.partition}:cloudformation:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stack/awseb-${aws_elastic_beanstalk_environment.app.id}-stack/*"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_deploy" {
  name = "${var.project_name}-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${local.github_oidc_repository}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "${var.project_name}-github-deploy"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UploadReleaseBundle"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.artifacts.arn}/releases/*"
      },
      {
        Sid      = "ReadReleaseBundle"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/releases/*"
      },
      {
        Sid    = "CreateApplicationVersion"
        Effect = "Allow"
        Action = ["elasticbeanstalk:CreateApplicationVersion"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:elasticbeanstalk:${var.aws_region}:${data.aws_caller_identity.current.account_id}:application/${aws_elastic_beanstalk_application.app.name}",
          "arn:${data.aws_partition.current.partition}:elasticbeanstalk:${var.aws_region}:${data.aws_caller_identity.current.account_id}:applicationversion/${aws_elastic_beanstalk_application.app.name}/github-*",
        ]
      },
      {
        Sid      = "UpdateEnvironment"
        Effect   = "Allow"
        Action   = ["elasticbeanstalk:UpdateEnvironment"]
        Resource = "arn:${data.aws_partition.current.partition}:elasticbeanstalk:${var.aws_region}:${data.aws_caller_identity.current.account_id}:environment/${aws_elastic_beanstalk_application.app.name}/${aws_elastic_beanstalk_environment.app.name}"
      },
      {
        # Beanstalk stages environment configuration in its own regional bucket,
        # even when the source bundle is stored in our separate artifacts bucket.
        Sid    = "BeanstalkStorageBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:GetBucket*",
          "s3:ListBucket",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketOwnershipControls",
        ]
        Resource = local.beanstalk_storage_arn
      },
      {
        Sid      = "BeanstalkStorageObjects"
        Effect   = "Allow"
        Action   = ["s3:Get*", "s3:Put*", "s3:DeleteObject", "s3:AbortMultipartUpload"]
        Resource = "${local.beanstalk_storage_arn}/*"
      },
      {
        Sid    = "UpdateEnvironmentStack"
        Effect = "Allow"
        Action = [
          "cloudformation:Describe*",
          "cloudformation:Get*",
          "cloudformation:ListStackResources",
          "cloudformation:UpdateStack",
          "cloudformation:CancelUpdateStack",
          "cloudformation:ContinueUpdateRollback",
          "cloudformation:TagResource",
          "cloudformation:UntagResource",
        ]
        Resource = local.beanstalk_stack_arn
      },
      {
        Sid      = "InspectEnvironmentInfrastructure"
        Effect   = "Allow"
        Action   = ["ec2:Describe*", "autoscaling:Describe*", "cloudformation:ValidateTemplate"]
        Resource = "*"
      },
      {
        Sid    = "DeployToEnvironmentInstances"
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:autoscaling:${var.aws_region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/awseb-${aws_elastic_beanstalk_environment.app.id}-stack-*"
      },
      {
        Sid      = "InspectEnvironmentRoles"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetInstanceProfile"]
        Resource = [aws_iam_role.beanstalk_service.arn, aws_iam_role.instance.arn, aws_iam_instance_profile.instance.arn]
      },
      {
        Sid      = "PassEnvironmentRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.beanstalk_service.arn, aws_iam_role.instance.arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["elasticbeanstalk.amazonaws.com", "ec2.amazonaws.com", "autoscaling.amazonaws.com", "cloudformation.amazonaws.com"]
          }
        }
      },
      {
        Sid      = "ReadDeploymentStatus"
        Effect   = "Allow"
        Action   = ["elasticbeanstalk:DescribeEnvironments"]
        Resource = "*"
      }
    ]
  })
}
