# Look up the SNS topic that already exists in AWS.
data "aws_sns_topic" "feedback" {
  name = var.sns_topic_name
}

# Dedicated least-privilege IAM user the Azure-hosted API uses to publish to the topic.
resource "aws_iam_user" "feedback_api" {
  name = "${local.name_prefix}-sns-publisher"
}

data "aws_iam_policy_document" "sns_publish" {
  statement {
    sid       = "PublishToFeedbackTopic"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [data.aws_sns_topic.feedback.arn]
  }
}

resource "aws_iam_user_policy" "sns_publish" {
  name   = "sns-publish"
  user   = aws_iam_user.feedback_api.name
  policy = data.aws_iam_policy_document.sns_publish.json
}

resource "aws_iam_access_key" "feedback_api" {
  user = aws_iam_user.feedback_api.name
}
