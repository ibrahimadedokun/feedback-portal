output "application_url" {
  description = "Public HTTPS frontend address. Publish public/ after provisioning."
  value       = "https://${azurerm_static_web_app.app.default_host_name}"
}

output "deployment_token" {
  description = "Set the AZURE_STATIC_WEB_APPS_API_TOKEN GitHub environment secret securely."
  value       = azurerm_static_web_app.app.api_key
  sensitive   = true
}

output "github_actions_variables" {
  value = {
    AZURE_DEPLOY_ENABLED  = "true"
    AZURE_APPLICATION_URL = "https://${azurerm_static_web_app.app.default_host_name}"
  }
}
