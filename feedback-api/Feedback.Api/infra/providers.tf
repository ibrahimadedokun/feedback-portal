provider "azurerm" {
  subscription_id = var.azure_subscription_id

  features {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}
