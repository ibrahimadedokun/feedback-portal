variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region with Container Apps Consumption capacity."
  type        = string
  default     = "uksouth"
}

variable "project_name" {
  type    = string
  default = "feedback-portal"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}[a-z0-9]$", var.project_name))
    error_message = "Use 2-22 lowercase letters, digits or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "container_image" {
  description = "Public image with an immutable tag or digest, e.g. ghcr.io/owner/feedback-portal:COMMIT_SHA."
  type        = string
  validation {
    condition     = can(regex("^[^\\s]+(:[^/]+|@sha256:[a-f0-9]{64})$", var.container_image))
    error_message = "Provide a container image with an explicit tag or SHA256 digest."
  }
}

variable "github_oidc_subject" {
  description = "Exact GitHub OIDC subject for the azure-production environment, including IDs if the repository uses immutable subjects."
  type        = string
  validation {
    condition     = startswith(var.github_oidc_subject, "repo:") && endswith(var.github_oidc_subject, ":environment:azure-production")
    error_message = "Use the exact repo:...:environment:azure-production subject for your repository."
  }
}

variable "feedback_mode" {
  description = "demo validates without delivery; sns delivers to the existing AWS topic."
  type        = string
  default     = "demo"
  validation {
    condition     = contains(["demo", "sns"], var.feedback_mode)
    error_message = "Choose demo or sns."
  }
}

variable "sns_topic_arn" {
  type    = string
  default = ""
}

variable "aws_credentials" {
  description = "SNS-only AWS identity. Pass with TF_VAR_aws_credentials; secret values are recorded in Terraform state."
  type = object({
    access_key_id     = string
    secret_access_key = string
    session_token     = optional(string, "")
  })
  sensitive = true
  default   = null
}
