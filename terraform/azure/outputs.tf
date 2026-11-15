output "application_url" {
  value = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "github_actions_variables" {
  value = {
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.github.client_id
    AZURE_TENANT_ID       = azurerm_user_assigned_identity.github.tenant_id
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    AZURE_RESOURCE_GROUP  = azurerm_resource_group.app.name
    AZURE_CONTAINER_APP   = azurerm_container_app.app.name
    AZURE_DEPLOY_ENABLED  = "true"
  }
}
