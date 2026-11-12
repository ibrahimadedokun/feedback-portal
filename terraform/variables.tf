variable "aws_region" {
  description = "AWS Region in which to create the application resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Lowercase project name used in AWS resource names."
  type        = string
  default     = "feedback-portal"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3-31 characters, start with a lowercase letter, and contain only lowercase letters, digits, or hyphens."
  }
}

variable "environment_name" {
  description = "Unique Elastic Beanstalk environment name."
  type        = string
  default     = "feedback-portal-prod"
}

variable "instance_type" {
  description = "EC2 instance type for the single-instance environment. Check current Free Tier eligibility before applying."
  type        = string
  default     = "t3.micro"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, in OWNER/REPOSITORY format."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use OWNER/REPOSITORY format."
  }
}

variable "github_repository_ids" {
  description = "GitHub owner and repository IDs for immutable OIDC subjects. Leave null only for repositories using the legacy subject format."
  type = object({
    owner_id      = string
    repository_id = string
  })
  default = null

  validation {
    condition = var.github_repository_ids == null ? true : (
      can(regex("^[0-9]+$", var.github_repository_ids.owner_id)) &&
      can(regex("^[0-9]+$", var.github_repository_ids.repository_id))
    )
    error_message = "GitHub owner_id and repository_id must both be numeric IDs."
  }
}

variable "github_branch" {
  description = "Only this branch may assume the GitHub Actions deployment role."
  type        = string
  default     = "main"
}

variable "sns_topic_arn" {
  description = "ARN of the existing standard SNS topic receiving feedback. Its subscriptions are managed outside this configuration."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z0-9-]+:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be a valid standard SNS topic ARN (FIFO topics are not supported)."
  }
}

variable "vpc_id" {
  description = "Optional VPC ID. Leave null to use the account's default VPC."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Optional subnet IDs in the selected VPC. Leave empty to use Elastic Beanstalk's default VPC selection."
  type        = list(string)
  default     = []
}
