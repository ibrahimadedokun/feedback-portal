variable "subscription_id" {
  description = "Azure subscription containing the frontend hosting."
  type        = string
}

variable "location" {
  description = "Resource group region. Retain the existing value when migrating."
  type        = string
  default     = "uksouth"
}

variable "site_location" {
  description = "Supported Static Web Apps region, independent of the resource group region."
  type        = string
  default     = "westeurope"
}

variable "project_name" {
  description = "Name of the Static Web App and prefix for the resource group."
  type        = string
  default     = "feedback-portal"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}[a-z0-9]$", var.project_name))
    error_message = "Use 2-22 lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}
