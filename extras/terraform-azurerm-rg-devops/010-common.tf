# Backend configuration
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.67.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "=3.5.1"
    }

    cloudinit = {
      source = "hashicorp/cloudinit"
      version = "=2.2.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # client_id       = "REPLACE-WITH-YOUR-CLIENT-ID"
  # client_secret   = "REPLACE-WITH-YOUR-CLIENT-SECRET"    
  # tenant_id       = "REPLACE-WITH-YOUR-TENANT-ID"
}

provider "random" {}

data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}
