data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_elastic_beanstalk_solution_stack" "node" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 v[0-9.]+ running Node.js 26$"
}

data "archive_file" "bootstrap" {
  type        = "zip"
  source_dir  = "${path.module}/.."
  output_path = "${path.module}/.terraform/bootstrap.zip"

  excludes = [
    ".git/**",
    ".github/**",
    ".env",
    ".env.*",
    "e2e/**",
    "node_modules/**",
    "terraform/**",
    "test/**",
    "test-results/**",
    "playwright-report/**",
    "README.md",
    "playwright.config.js",
  ]
}

resource "random_id" "artifact_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}-${random_id.artifact_bucket.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-release-bundles"
    status = "Enabled"

    filter {
      prefix = "releases/"
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_object" "bootstrap" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "bootstrap/application.zip"
  source = data.archive_file.bootstrap.output_path
  etag   = filemd5(data.archive_file.bootstrap.output_path)

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = var.project_name
  description = "Feedback portal Node.js application"
}

resource "aws_elastic_beanstalk_application_version" "bootstrap" {
  name        = "terraform-bootstrap"
  application = aws_elastic_beanstalk_application.app.name
  description = "Initial application bundle managed by Terraform"
  bucket      = aws_s3_bucket.artifacts.id
  key         = aws_s3_object.bootstrap.key
}

resource "aws_iam_role" "beanstalk_service" {
  name = "${var.project_name}-eb-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "elasticbeanstalk.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "beanstalk_health" {
  role       = aws_iam_role.beanstalk_service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "beanstalk_updates" {
  role       = aws_iam_role.beanstalk_service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "instance" {
  name = "${var.project_name}-eb-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "instance_web_tier" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy" "instance_app_access" {
  name = "${var.project_name}-app-access"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadApplicationBundles"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid      = "PublishFeedback"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.sns_topic_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "beanstalk_artifact_read" {
  name = "${var.project_name}-artifact-read"
  role = aws_iam_role.beanstalk_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadApplicationBundles"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid      = "ListArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.artifacts.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-eb-instance"
  role = aws_iam_role.instance.name
}

resource "aws_elastic_beanstalk_environment" "app" {
  name                = var.environment_name
  application         = aws_elastic_beanstalk_application.app.name
  version_label       = aws_elastic_beanstalk_application_version.bootstrap.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.node.name

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.instance.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "DisableIMDSv1"
    value     = "true"
  }

  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "basic"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "PORT"
    value     = "8080"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "FEEDBACK_MODE"
    value     = "sns"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "SNS_TOPIC_ARN"
    value     = var.sns_topic_arn
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "AWS_REGION"
    value     = split(":", var.sns_topic_arn)[3]
  }

  dynamic "setting" {
    for_each = local.network_settings
    content {
      namespace = "aws:ec2:vpc"
      name      = setting.value.name
      value     = setting.value.value
    }
  }

  lifecycle {
    ignore_changes = [version_label]

    precondition {
      condition     = length(var.subnet_ids) == 0 || var.vpc_id != null
      error_message = "Set vpc_id when specifying subnet_ids."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.beanstalk_health,
    aws_iam_role_policy_attachment.beanstalk_updates,
    aws_iam_role_policy_attachment.instance_web_tier,
    aws_iam_role_policy.instance_app_access,
    aws_iam_role_policy.beanstalk_artifact_read,
  ]
}

locals {
  network_settings = concat(
    var.vpc_id == null ? [] : [{ name = "VPCId", value = var.vpc_id }],
    length(var.subnet_ids) == 0 ? [] : [{ name = "Subnets", value = join(",", var.subnet_ids) }],
    [{ name = "AssociatePublicIpAddress", value = "true" }]
  )
}
