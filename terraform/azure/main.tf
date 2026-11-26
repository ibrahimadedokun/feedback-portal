locals {
  tags = { Project = var.project_name, ManagedBy = "Terraform" }
}

# Preserve this resource address/name for existing Azure deployments.
resource "azurerm_resource_group" "app" {
  name     = "${var.project_name}-azure"
  location = var.location
  tags     = local.tags
}

resource "azurerm_static_web_app" "app" {
  name                = var.project_name
  resource_group_name = azurerm_resource_group.app.name
  location            = var.site_location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = local.tags

  # The deployment action can populate these without Terraform owning CI.
  lifecycle {
    ignore_changes = [repository_branch, repository_url]
  }
}
