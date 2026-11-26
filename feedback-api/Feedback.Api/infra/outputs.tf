output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "container_app_name" {
  value = azurerm_container_app.api.name
}

output "container_app_url" {
  value = "https://${azurerm_container_app.api.ingress[0].fqdn}"
}

output "container_image" {
  value = var.container_image
}

output "sns_topic_arn" {
  value = data.aws_sns_topic.feedback.arn
}
