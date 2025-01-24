  terraform {
    required_version = ">= 1.3.0"
    required_providers {
      azurerm = {
        source  = "hashicorp/azurerm"
        version = "= 4.16.0"
      }
    }
  }

  provider "azurerm" {
    features {}
    subscription_id = "131c8c8b-70b5-4c73-8d6c-ac3389512993"
  }

  # Resource Group
  resource "azurerm_resource_group" "aks_rg" {
    name     = "aks-resource-group"
    location = "eastus"
  }

  # Virtual Network
  resource "azurerm_virtual_network" "aks_vnet" {
    name                = "aks-vnet"
    location            = azurerm_resource_group.aks_rg.location
    resource_group_name = azurerm_resource_group.aks_rg.name
    address_space       = ["10.0.0.0/16"]
  }

  # Subnet for AKS
  resource "azurerm_subnet" "aks_subnet" {
    name                 = "aks-subnet"
    resource_group_name  = azurerm_resource_group.aks_rg.name
    virtual_network_name = azurerm_virtual_network.aks_vnet.name
    address_prefixes     = ["10.0.1.0/24"]

  }

  # Azure Kubernetes Service
  resource "azurerm_kubernetes_cluster" "aks" {
    name                = "aks-cluster"
    location            = azurerm_resource_group.aks_rg.location
    resource_group_name = azurerm_resource_group.aks_rg.name
    dns_prefix          = "aksdns"

 network_profile {
    network_plugin    = "azure"
    service_cidr     = "172.16.0.0/16"
    dns_service_ip   = "172.16.0.10"
  }
    default_node_pool {
      name       = "systempool"
      vm_size    = "Standard_DS2_v2"
      node_count = 2
      vnet_subnet_id = azurerm_subnet.aks_subnet.id
    }

    identity {
      type = "SystemAssigned"
    }

    azure_active_directory_role_based_access_control {
      admin_group_object_ids = ["78763cc5-6db7-4df0-be01-1e7f7a2cc0ce"]
    }

    tags = {
      environment = "production"
    }
  }
