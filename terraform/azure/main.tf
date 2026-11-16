locals {
  tags = { Project = var.project_name, ManagedBy = "Terraform" }
  aws_secrets = var.feedback_mode == "sns" && var.aws_credentials != null ? merge({
    "aws-access-key-id"     = var.aws_credentials.access_key_id
    "aws-secret-access-key" = var.aws_credentials.secret_access_key
    }, var.aws_credentials.session_token != "" ? {
    "aws-session-token" = var.aws_credentials.session_token
  } : {}) : {}
  aws_secret_names = try(nonsensitive(toset(keys(local.aws_secrets))), toset(keys(local.aws_secrets)))
  secret_env_names = {
    "aws-access-key-id"     = "AWS_ACCESS_KEY_ID"
    "aws-secret-access-key" = "AWS_SECRET_ACCESS_KEY"
    "aws-session-token"     = "AWS_SESSION_TOKEN"
  }
}

resource "azurerm_resource_group" "app" {
  name     = "${var.project_name}-azure"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_app_environment" "app" {
  name                = "${var.project_name}-env"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  tags                = local.tags

  # No dedicated nodes, Log Analytics workspace or persisted log ingestion.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app" "app" {
  name                         = var.project_name
  container_app_environment_id = azurerm_container_app_environment.app.id
  resource_group_name          = azurerm_resource_group.app.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.tags

  dynamic "secret" {
    for_each = local.aws_secret_names
    content {
      name  = secret.value
      value = local.aws_secrets[secret.value]
    }
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 3000
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
      name   = "feedback-portal"
      image  = var.container_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "PORT"
        value = "3000"
      }
      env {
        name  = "FEEDBACK_MODE"
        value = var.feedback_mode
      }
      env {
        name  = "SNS_TOPIC_ARN"
        value = var.sns_topic_arn
      }
      env {
        name  = "AWS_REGION"
        value = try(split(":", var.sns_topic_arn)[3], "")
      }
      dynamic "env" {
        for_each = local.aws_secret_names
        content {
          name        = local.secret_env_names[env.value]
          secret_name = env.value
        }
      }

      readiness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/api/config"
      }
      liveness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/api/config"
      }
    }
  }

  lifecycle {
    # GitHub Actions owns subsequent image releases. Set container_image to the
    # current release before removing this rule or recreating the app.
    ignore_changes = [template[0].container[0].image]
    precondition {
      condition     = var.feedback_mode != "sns" || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:.+$", var.sns_topic_arn))
      error_message = "SNS mode requires sns_topic_arn to be a valid AWS SNS topic ARN."
    }
    precondition {
      condition = var.feedback_mode != "sns" || try(
        length(trimspace(var.aws_credentials.access_key_id)) > 0 && length(trimspace(var.aws_credentials.secret_access_key)) > 0,
        false
      )
      error_message = "SNS mode requires aws_credentials with non-empty access_key_id and secret_access_key. In PowerShell run ./Set-AwsCredentials.ps1 (optionally -Profile YOUR_PROFILE), or set TF_VAR_aws_credentials to a JSON object before planning. AWS CLI credentials are not automatically passed to the Azure container. The identity must have sns:Publish permission on sns_topic_arn."
    }
  }
}

resource "azurerm_user_assigned_identity" "github" {
  name                = "${var.project_name}-github"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  name      = "github-azure-production"
  parent_id = azurerm_user_assigned_identity.github.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = var.github_oidc_subject
}

resource "azurerm_role_assignment" "github" {
  scope                = azurerm_container_app.app.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}
