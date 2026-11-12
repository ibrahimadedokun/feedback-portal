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
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
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
        Sid      = "CreateApplicationVersion"
        Effect   = "Allow"
        Action   = ["elasticbeanstalk:CreateApplicationVersion"]
        Resource = "arn:${data.aws_partition.current.partition}:elasticbeanstalk:${var.aws_region}:${data.aws_caller_identity.current.account_id}:application/${aws_elastic_beanstalk_application.app.name}"
      },
      {
        Sid      = "UpdateEnvironment"
        Effect   = "Allow"
        Action   = ["elasticbeanstalk:UpdateEnvironment"]
        Resource = "arn:${data.aws_partition.current.partition}:elasticbeanstalk:${var.aws_region}:${data.aws_caller_identity.current.account_id}:environment/${aws_elastic_beanstalk_application.app.name}/${aws_elastic_beanstalk_environment.app.name}"
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
