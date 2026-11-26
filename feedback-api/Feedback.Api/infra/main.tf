resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.1
  tags                = local.tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${local.name_prefix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  logs_destination           = "log-analytics"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.tags
}

resource "azurerm_container_app" "api" {
  name                         = "app-${local.name_prefix}-${local.suffix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  max_inactive_revisions       = 2

  secret {
    name  = "aws-access-key-id"
    value = aws_iam_access_key.feedback_api.id
  }

  secret {
    name  = "aws-secret-access-key"
    value = aws_iam_access_key.feedback_api.secret
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }

    container {
      name   = "api"
      image  = var.container_image
      cpu    = 0.25
      memory = "0.5Gi"

      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health"
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 30
      }

      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/health"
        interval_seconds = 10
        timeout          = 3
      }

      liveness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/health"
        interval_seconds = 30
        timeout          = 3
      }

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = "Production"
      }
      env {
        name  = "Sns__TopicArn"
        value = data.aws_sns_topic.feedback.arn
      }
      env {
        name  = "AWS__Region"
        value = var.aws_region
      }
      env {
        name        = "AWS__AccessKeyId"
        secret_name = "aws-access-key-id"
      }
      env {
        name        = "AWS__SecretAccessKey"
        secret_name = "aws-secret-access-key"
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health"
        interval_seconds        = 5
        failure_count_threshold = 30
      }
      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/health"
        interval_seconds = 10
      }
      liveness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/health"
        interval_seconds = 30
      }
    }
  }

  depends_on = [aws_iam_user_policy.sns_publish]
  tags       = local.tags
}
