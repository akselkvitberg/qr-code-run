terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.3.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "0.4.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "1.12.0"
    }
  }
  experiments = [module_variable_optional_attrs]

  backend "azurerm" {
    resource_group_name  = "BCC-Platform"
    storage_account_name = "bccplatformtfstate"
    container_name       = "tfstate"
    key                  = "qr-code-run.terraform.tfstate"
  }

}

provider "azurerm" {
  features {}
}

provider "azapi" {
}

provider "postgresql" {
  superuser = false
  host      = data.azurerm_postgresql_flexible_server.postgresql_server.fqdn
  database  =  local.resource_prefix
  username  = "psqladmin"
  password  = data.azurerm_key_vault_secret.postgresql_admin_password.value
  sslmode   = "require"
}

data "azurerm_client_config" "current" {}

locals {
    location        = "norwayeast"
    resource_group  = "qr-code-run-${var.environment}"
    resource_prefix = "qr-code-run-prod"
    platform_resource_prefix = "qr-code-run-${var.environment}"
    platform_resource_group  = "qr-code-run-${var.environment}"
    storage_account_name     = "${replace(local.platform_resource_prefix,"-","")}"
    tags            = {}
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
  name     = local.resource_group
  location = local.location
  tags     = local.tags
}


# Vault for postgresql
resource "azurerm_key_vault" "postgresql_vault" {
  name                = lower(replace("${local.resource_prefix}-psql","-",""))
  location            = local.location
  resource_group_name = local.resource_group
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  purge_protection_enabled = true
  enabled_for_disk_encryption = true
  # access_policy {
  #   tenant_id = data.azurerm_client_config.current.tenant_id
  #   object_id = data.azurerm_client_config.current.object_id
  #   # key_permissions = [
  #   #   "Get", "UnwrapKey", "WrapKey"
  #   # ]
  #   # secret_permissions = [
  #   #   "Get", "Backup", "Delete", "List", "Purge", "Recover", "Restore", "Set",
  #   # ]
  #   # storage_permissions = [
  #   #   "Get"
  #   # ]
  # }
  enable_rbac_authorization = true
}

# Admin Password for Postgresql
resource "random_password" "postgreql_admin_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store admin password in Azure Key vault
resource "azurerm_key_vault_secret" "postgreql_admin_password" {
  name         = "postgreql-admin-password"
  value        = random_password.postgreql_admin_password.result
  key_vault_id = azurerm_key_vault.postgresql_vault.id
  depends_on = [ azurerm_key_vault.postgresql_vault ]
}

# Postgresql server
resource "azurerm_postgresql_flexible_server" "postgresql" {
  name                = "${local.resource_prefix}-postgresql"
  location            = local.location
  resource_group_name = local.resource_group

  administrator_login          = "psqladmin"
  administrator_password       = azurerm_key_vault_secret.postgreql_admin_password.value

  sku_name                     = "B_Standard_B1ms"
  version                      = "13"
  storage_mb                   = 32768

  backup_retention_days        = 35
  geo_redundant_backup_enabled = false
  create_mode = "Default"

  tags                          = local.tags

  zone                          = "1"

  # delegated_subnet_id = 
  # private_dns_zone_id =

}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

# Open firewall for machine deploying server
resource "azurerm_postgresql_flexible_server_firewall_rule" "terraform_deploy_ip" {
  name             = "terraform_deploy_ip"
  server_id        = azurerm_postgresql_flexible_server.postgresql.id
  start_ip_address = "${chomp(data.http.myip.body)}"
  end_ip_address   = "${chomp(data.http.myip.body)}"
}

# Get Container Registry
data "azurerm_container_registry" "acr" {
  name                = "bccplatform"
  resource_group_name = "BCC-Platform"
}

# Get Key Vault for postgresql server
data "azurerm_key_vault" "keyvault" {
  name                = lower(replace("${local.platform_resource_prefix}-psql","-",""))
  resource_group_name = local.platform_resource_group
}

# Get Admin password for postgresql server
data "azurerm_key_vault_secret" "postgresql_admin_password" {
  name         = "postgreql-admin-password"
  key_vault_id = data.azurerm_key_vault.keyvault.id
}

# Get Postgresql Server
data "azurerm_postgresql_flexible_server" "postgresql_server" {
  name                   = "${local.platform_resource_prefix}-postgresql"
  resource_group_name    = local.platform_resource_group
}

# Get platform resource group
data "azurerm_resource_group" "platform_rg" {
  name = local.platform_resource_group
}

# Create Database
# NB! This will only work if server has a public IP and the client execuring terrafrom has been whitelisted in the server's firewall
# Perhaps whitelisting the IP address of the current client can be automated...
module "postgresql_db" {
  source             = "./modules/azure/postgresql_db"
  db_name            = local.resource_prefix
  server_resource_id = data.azurerm_postgresql_flexible_server.postgresql_server.id
  depends_on = [
    azurerm_postgresql_flexible_server_firewall_rule.terraform_deploy_ip
  ]
}

# Store db user password
resource "azurerm_key_vault_secret" "postgreql_user_password" {
  name         = "${local.resource_prefix}-db-user-password"
  value        = module.postgresql_db.db_user_password
  key_vault_id = data.azurerm_key_vault.keyvault.id
}

# Redis Cache
resource "azurerm_redis_cache" "redis_cache" {
  name                = "${local.resource_prefix}-redis"
  location            = local.location
  resource_group_name = local.resource_group
  capacity            = 0
  family              = "C"
  sku_name            = "Basic"
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  public_network_access_enabled = false

  redis_configuration {
  }
}

# Private DNS zone

resource "azurerm_private_dns_zone" "redis_dns_zone" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = local.resource_group
}

# Redis private endpoint
resource "azurerm_private_endpoint" "redis_endpoint" {
  name                = "${local.resource_prefix}-redis-endpoint"
  location            = local.location
  resource_group_name = local.resource_group
  subnet_id           = module.container_apps_vlan.subnet_id

  private_service_connection {
    name                              = "${local.resource_prefix}-redis-endpoint-connection"
    private_connection_resource_id    =  azurerm_redis_cache.redis_cache.id
    is_manual_connection              = false
    subresource_names                 = ["redisCache"]
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.redis_dns_zone.id
    ]
  }
}

# Analytics Workspace
module "log_analytics_workspace" {
  source                           = "./modules/azure/log_analytics"
  name                             = "${local.resource_prefix}-logs"
  location                         = local.location
  resource_group_name              = azurerm_resource_group.rg.name
  tags                             = local.tags

}

# Application Insights
module "application_insights" {
  source                           = "./modules/azure/application_insights"
  name                             = "${local.resource_prefix}-env-insights"
  location                         = local.location
  resource_group_name              = azurerm_resource_group.rg.name
  tags                             = local.tags
  application_type                 = "web"
  workspace_id                     = module.log_analytics_workspace.id
}


# VLAN for Container Environment
module "container_apps_vlan" {
  source                           = "./modules/azure/container_apps_vlan"
  name                             = "${local.resource_prefix}-vlan"
  location                         = local.location
  resource_group_name              = azurerm_resource_group.rg.name
  tags                             = local.tags

  depends_on = [
    azurerm_resource_group.rg
  ]
}


# Create Static App for Frontend

resource "azurerm_static_site" "ui" {
  name                = "${local.resource_prefix}-ui"
  resource_group_name = azurerm_resource_group.rg.name
  location            = "westeurope"
  sku_tier            = "Standard"
}



# Create Azure Application for Github Deployment


# Container Environment
module "container_apps_env"  {
  source                           = "./modules/azure/container_apps_env"
  managed_environment_name         = "${local.resource_prefix}-env"
  location                         = local.location
  resource_group_id                = azurerm_resource_group.rg.id
  tags                             = local.tags
  instrumentation_key              = module.application_insights.instrumentation_key
  workspace_id                     = module.log_analytics_workspace.workspace_id
  primary_shared_key               = module.log_analytics_workspace.primary_shared_key
  vlan_subnet_id                   = module.container_apps_vlan.subnet_id
}



# API Container App
module "api_container_app" {
  source                           = "./modules/azure/container_apps"
  managed_environment_id           = module.container_apps_env.id
  location                         = local.location
  resource_group_id                = azurerm_resource_group.rg.id
  tags                             = local.tags
  container_app                   = {
    name              = "${local.resource_prefix}-api"
    configuration      = {
      ingress          = {
        external       = true
        targetPort     = 5125
      }
      dapr             = {
        enabled        = true
        appId          = "${local.resource_prefix}-api"
        appProtocol    = "http"
        appPort        = 5125
      }
      secrets          = [
          {
            name    = "postgresql-password"
            value   =  module.postgresql_db.db_user_password
          },
          {
            name    = "redis-connection-string"
            value   =  azurerm_redis_cache.redis_cache.primary_connection_string
          },
          {
            name    = "application-insights-connection-string"
            value   =  module.application_insights.connection_string
          }#,
          # {
          #   name    = "new-relic-licence-key"
          #   value   =  var.new-relic-licence-key
          # }
        ]
    }
    template          = {
      containers      = [{
        image         = "hello-world:latest" // "bccplatform.azurecr.io/bcc-code-run-prod-api:latest"
        name          = "bcc-code-run-api"
        env           = [{
            name        = "APP_PORT"
            value       = 80
          },
          {
            name        = "POSTGRES_HOST"
            value       = data.azurerm_postgresql_flexible_server.postgresql_server.fqdn
          },
          {
            name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
            secretRef   = "application-insights-connection-string"
          },
          {
            name        = "APPLICATIONINSIGHTS__CONNECTIONSTRING"
            secretRef   = "application-insights-connection-string"
          },
          {
            name        = "POSTGRES_PORT"
            value       = 5432
          },
          {
            name        = "POSTGRES_DB"
            value       = module.postgresql_db.db_name
          },
          {
            name        = "POSTGRES_USER"
            value       = module.postgresql_db.db_user_username
          },
          {
            name        = "POSTGRES_PASSWORD"
            secretRef   = "postgresql-password"
          },
          {
            name        = "REDIS_CONNECTION_STRING"
            secretRef   = "redis-connection-string"
          },
          {
            name        = "ENVIRONMENT_NAME"
            value   = terraform.workspace
          } #,
          # {
          #   name        = "NEW_RELIC_LICENSE_KEY"
          #   secretRef   = "new-relic-licence-key"
          # },
          # {
          #   name        = "NEW_RELIC_APP_NAME"
          #   value       = "buk-universal-games-dev-az"
          # },
        ]
        resources     = {
          cpu         = 0.5
          memory      = "1Gi"
        }
      }]
      scale           = {
        minReplicas   = 0
        maxReplicas   = 10
      }
    }
  }
}


# File Storage for CMS (directus)

resource "azurerm_storage_account" "file_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  tags                     = local.tags
}

resource "azurerm_storage_container" "file_storage_container" {
  name                  = "files"
  storage_account_name  = azurerm_storage_account.file_storage.name
  container_access_type = "blob"
}


# Generate password for directus
resource "random_password" "directus_admin_pw" {
  length           = 32
  special          = true
  override_special = "!#*()-_=+[]:?"
}

resource "random_uuid" "directus_key" {
}
resource "random_uuid" "directus_secret" {
}

# Directus Container App
module "directus_container_app" {
  source                           = "./modules/azure/container_apps"
  managed_environment_id           = module.container_apps_env.id
  location                         = local.location
  resource_group_id                = azurerm_resource_group.rg.id
  tags                             = local.tags
  container_app                   = {
    name              = "${local.resource_prefix}-directus"
    configuration      = {
      ingress          = {
        external       = true
        targetPort     = 8055
      }
      dapr             = {
        enabled        = true
        appId          = "${local.resource_prefix}-directus"
        appProtocol    = "http"
        appPort        = 8055
      }
      secrets          = [
        {
          name    = "postgresql-password"
          value   =  module.postgresql_db.db_user_password
        },
        {
          name    = "redis-connection-string"
          value   =  "rediss://:${azurerm_redis_cache.redis_cache.primary_access_key}@${azurerm_redis_cache.redis_cache.hostname}:${azurerm_redis_cache.redis_cache.ssl_port}/0"
        },
        {
          name    = "directus-admin-user-pw"
          value   =  random_password.directus_admin_pw.result
        },
        {
          name    = "directus-storage-secret"
          value   =  random_uuid.directus_secret.result
        },
        {
          name    = "azure-storage-key"
          value   =  azurerm_storage_account.file_storage.primary_access_key
        }
      ]
    }
    template          = {
      containers      = [{
        image         = "directus/directus:latest"
        name          = "universal-games-directus"
        env           = [{
          name        = "APP_PORT"
          value       = 8055
        },
        {
          name        = "KEY"
          value       = random_uuid.directus_key.result
        },
        {
          name        = "STORAGE_LOCATIONS"
          value       = "az"
        },
        {
          name        = "STORAGE_AZ_DRIVER"
          value       = "azure"
        },
        {
          name        = "STORAGE_AZ_CONTAINER_NAME"
          value       = azurerm_storage_container.file_storage_container.name
        },
        {
          name        = "STORAGE_AZ_ACCOUNT_NAME"
          value       = local.storage_account_name
        },
        {
          name        = "STORAGE_AZ_ACCOUNT_KEY"
          secretRef   = "azure-storage-key"
        },
        {
          name        = "STORAGE_AZ_ENDPOINT"
          value       = azurerm_storage_account.file_storage.primary_web_endpoint
        },
        {
          name        = "SECRET"
          secretRef   = "directus-storage-secret"
        },
        {
          name        = "ADMIN_EMAIL"
          value       = "it@bcc.no"
        },
        {
          name        = "ADMIN_PASSWORD"
          secretRef   = "directus-admin-user-pw"
        },
        {
          name        = "DB_CLIENT"
          value       = "pg"
        },
        {
          name        = "DB_HOST"
          value       = data.azurerm_postgresql_flexible_server.postgresql_server.fqdn
        },
        {
          name        = "DB_PORT"
          value       = 5432
        },
        {
          name        = "DB_SSL"
          value       = true
        },
        {
          name        = "DB_DATABASE"
          value       = module.postgresql_db.db_name
        },
        {
          name        = "DB_USER"
          value       = module.postgresql_db.db_user_username
        },
        {
          name        = "DB_PASSWORD"
          secretRef   = "postgresql-password"
        },
        {
          name        = "CACHE_ENABLED"
          value       = true
        },
        {
          name        = "CACHE_STORE"
          value       = "redis"
        },
        {
          name        = "CACHE_REDIS"
          secretRef   = "redis-connection-string"
        }
        
        ]
        resources     = {
          cpu         = 0.5
          memory      = "1Gi"
        }
      }]
      scale           = {
        minReplicas   = 0
        maxReplicas   = 1
      }
    }
  }
}
