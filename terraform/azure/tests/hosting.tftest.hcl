mock_provider "azurerm" {
  mock_resource "azurerm_static_web_app" {
    defaults = {
      default_host_name = "example.azurestaticapps.net"
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "uksouth"
  site_location   = "westeurope"
}

run "free_static_hosting" {
  command = apply

  assert {
    condition = (
      azurerm_static_web_app.app.sku_tier == "Free" &&
      azurerm_static_web_app.app.sku_size == "Free"
    )
    error_message = "Azure frontend hosting must use the Free plan."
  }

  assert {
    condition = (
      azurerm_resource_group.app.location == "uksouth" &&
      azurerm_static_web_app.app.location == "westeurope" &&
      azurerm_static_web_app.app.resource_group_name == azurerm_resource_group.app.name
    )
    error_message = "Keep the existing group region independent of the supported Static Web Apps region."
  }

  assert {
    condition     = output.application_url == "https://example.azurestaticapps.net"
    error_message = "The frontend URL must use the Static Web Apps hostname over HTTPS."
  }
}
