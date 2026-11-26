variable "azure_subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "app_name" {
  description = "Base name used for resource naming."
  type        = string
  default     = "feedback-api"
}

variable "environment" {
  description = "Environment name (e.g. dev, test, prod)."
  type        = string
  default     = "dev"
}

variable "container_image" {
  description = "Public GHCR image reference, pinned to a commit tag or sha256 digest."
  type        = string

  validation {
    condition     = can(regex("^ghcr\\.io/[a-z0-9._/-]+(:[a-zA-Z0-9._-]+|@sha256:[a-f0-9]{64})$", var.container_image))
    error_message = "Use a ghcr.io image reference with an explicit tag or sha256 digest."
  }
}

variable "aws_region" {
  description = "AWS region where the existing SNS topic lives."
  type        = string
  default     = "us-east-1"
}

variable "sns_topic_name" {
  description = "Name of the existing SNS topic the API publishes to."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
