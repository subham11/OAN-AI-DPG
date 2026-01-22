# ==============================================================================
# Azure Compute Resources - Virtual Machine Scale Set
# ==============================================================================

# ------------------------------------------------------------------------------
# User Data Script (Cloud-Init)
# ------------------------------------------------------------------------------
locals {
  custom_data = base64encode(templatefile("${path.module}/templates/cloud_init.yaml.tpl", {
    nvidia_driver_version = var.nvidia_driver_version
    cuda_version          = var.cuda_version
    health_check_port     = var.health_check_port
    environment           = var.environment
  }))
}

# ------------------------------------------------------------------------------
# Virtual Machine Scale Set with GPU
# ------------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine_scale_set" "gpu" {
  name                = "${var.name_prefix}-vmss"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.instance_type
  instances           = var.asg_desired_capacity

  admin_username = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = var.root_volume_size
  }

  network_interface {
    name    = "${var.name_prefix}-nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.private[0].id
      load_balancer_backend_address_pool_ids = var.enable_load_balancer ? [azurerm_lb_backend_address_pool.main[0].id] : []
    }
  }

  # Custom data for NVIDIA installation
  custom_data = local.custom_data

  # Health probe for VMSS
  health_probe_id = var.enable_load_balancer ? azurerm_lb_probe.health[0].id : null

  # Automatic repairs
  automatic_instance_repair {
    enabled      = true
    grace_period = "PT30M"
  }

  # Upgrade policy
  upgrade_mode = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 50
    max_unhealthy_instance_percent          = 50
    max_unhealthy_upgraded_instance_percent = 50
    pause_time_between_batches              = "PT5M"
  }

  # Extension for NVIDIA GPU drivers
  extension {
    name                       = "NvidiaGpuDriverLinux"
    publisher                  = "Microsoft.HpcCompute"
    type                       = "NvidiaGpuDriverLinux"
    type_handler_version       = "1.9"
    auto_upgrade_minor_version = true
  }

  # Extension for Azure Monitor
  extension {
    name                       = "AzureMonitorLinuxAgent"
    publisher                  = "Microsoft.Azure.Monitor"
    type                       = "AzureMonitorLinuxAgent"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.common_tags, {
    GPUInstance = "true"
  })

  lifecycle {
    ignore_changes = [instances]
  }
}

# ------------------------------------------------------------------------------
# SSH Key (if not provided)
# ------------------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  count = var.ssh_public_key == "" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# ------------------------------------------------------------------------------
# Auto-Scale Settings
# ------------------------------------------------------------------------------
resource "azurerm_monitor_autoscale_setting" "gpu" {
  name                = "${var.name_prefix}-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.gpu.id

  profile {
    name = "default"

    capacity {
      default = var.asg_desired_capacity
      minimum = var.asg_min_size
      maximum = var.asg_max_size
    }

    # Scale out rule
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.gpu.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_up_cpu_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in rule
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.gpu.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.scale_down_cpu_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator    = true
      send_to_subscription_co_administrator = false
    }
  }

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Log Analytics Workspace for Monitoring
# ------------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Diagnostic Settings for VMSS
# ------------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "vmss" {
  name                       = "${var.name_prefix}-vmss-diag"
  target_resource_id         = azurerm_linux_virtual_machine_scale_set.gpu.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
