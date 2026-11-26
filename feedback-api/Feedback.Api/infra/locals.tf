locals {
  name_prefix = "${var.app_name}-${var.environment}"

  # Keep the existing suffix when migrating from App Service to Container Apps.
  suffix = random_string.suffix.result

  tags = merge({
    application = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)
}

resource "random_string" "suffix" {
  length  = 3
  upper   = false
  special = false
}
