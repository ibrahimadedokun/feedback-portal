variable "aws_region" {
  description = "Region for the private website bucket. Global WAF uses us-east-1."
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Lowercase prefix for static hosting resources."
  type        = string
  default     = "feedback-portal"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "Use 3-31 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "github_repository" {
  description = "Repository permitted to publish frontend assets, in OWNER/REPOSITORY format."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use OWNER/REPOSITORY format."
  }
}

variable "github_repository_ids" {
  description = "Numeric IDs for repositories using immutable GitHub OIDC subjects; otherwise null."
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
    error_message = "Both GitHub IDs must be numeric."
  }
}

variable "github_branch" {
  description = "Deployment branch; must match deploy-aws.yml."
  type        = string
  default     = "develop"
}
