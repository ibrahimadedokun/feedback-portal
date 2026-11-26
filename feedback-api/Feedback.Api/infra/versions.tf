terraform {
  required_version = ">= 1.17.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.15"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.74"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Recommended: store state remotely. The state contains the AWS IAM secret access key,
  # so the backend must be access-restricted. Uncomment, fill in, then run `terraform init -migrate-state`.
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstatexxxx"
  #   container_name       = "tfstate"
  #   key                  = "feedback-api.tfstate"
  #   use_azuread_auth     = true
  # }
}
