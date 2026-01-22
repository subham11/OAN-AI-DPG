# ==============================================================================
# Azure Scheduler Resources - Automation Account
# ==============================================================================
# Scheduling: IST 9:30 AM (04:00 UTC) to Ethiopia Time 6:00 PM (15:00 UTC)
# ==============================================================================

# ------------------------------------------------------------------------------
# Automation Account
# ------------------------------------------------------------------------------
resource "azurerm_automation_account" "main" {
  count = var.enable_scheduling ? 1 : 0

  name                = "${var.name_prefix}-automation"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Role Assignment for Automation Account
# ------------------------------------------------------------------------------
resource "azurerm_role_assignment" "automation_contributor" {
  count = var.enable_scheduling ? 1 : 0

  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.main[0].identity[0].principal_id
}

# ------------------------------------------------------------------------------
# Start VMSS Runbook
# ------------------------------------------------------------------------------
resource "azurerm_automation_runbook" "start_vmss" {
  count = var.enable_scheduling ? 1 : 0

  name                    = "${var.name_prefix}-start-vmss"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"

  content = <<-POWERSHELL
    # Start VMSS Runbook
    # Runs at IST 9:30 AM (04:00 UTC)
    
    param(
        [string]$ResourceGroupName = "${azurerm_resource_group.main.name}",
        [string]$VMSSName = "${azurerm_linux_virtual_machine_scale_set.gpu.name}",
        [int]$DesiredCapacity = ${var.asg_desired_capacity}
    )
    
    try {
        Write-Output "Starting VMSS: $VMSSName in Resource Group: $ResourceGroupName"
        Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
        
        # Connect using managed identity
        Connect-AzAccount -Identity
        
        # Get current VMSS state
        $vmss = Get-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName
        $currentCapacity = $vmss.Sku.Capacity
        
        Write-Output "Current capacity: $currentCapacity"
        Write-Output "Target capacity: $DesiredCapacity"
        
        if ($currentCapacity -lt $DesiredCapacity) {
            # Update VMSS capacity
            $vmss.Sku.Capacity = $DesiredCapacity
            Update-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName -VirtualMachineScaleSet $vmss
            
            Write-Output "Successfully updated VMSS capacity to $DesiredCapacity"
        } else {
            Write-Output "VMSS already has sufficient capacity"
        }
        
        # Start all instances
        Start-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName
        Write-Output "Successfully started VMSS instances"
        
    } catch {
        Write-Error "Error starting VMSS: $_"
        throw $_
    }
  POWERSHELL

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Stop VMSS Runbook
# ------------------------------------------------------------------------------
resource "azurerm_automation_runbook" "stop_vmss" {
  count = var.enable_scheduling ? 1 : 0

  name                    = "${var.name_prefix}-stop-vmss"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main[0].name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"

  content = <<-POWERSHELL
    # Stop VMSS Runbook
    # Runs at Ethiopia Time 6:00 PM (15:00 UTC)
    
    param(
        [string]$ResourceGroupName = "${azurerm_resource_group.main.name}",
        [string]$VMSSName = "${azurerm_linux_virtual_machine_scale_set.gpu.name}"
    )
    
    try {
        Write-Output "Stopping VMSS: $VMSSName in Resource Group: $ResourceGroupName"
        Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
        
        # Connect using managed identity
        Connect-AzAccount -Identity
        
        # Get current VMSS state
        $vmss = Get-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName
        $currentCapacity = $vmss.Sku.Capacity
        
        Write-Output "Current capacity: $currentCapacity"
        
        # Stop and deallocate all instances
        Stop-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName -Force
        Write-Output "Successfully stopped VMSS instances"
        
        # Optionally set capacity to 0 to save costs
        $vmss.Sku.Capacity = 0
        Update-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName -VirtualMachineScaleSet $vmss
        Write-Output "Set VMSS capacity to 0"
        
    } catch {
        Write-Error "Error stopping VMSS: $_"
        throw $_
    }
  POWERSHELL

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Schedule for Start VMSS - IST 9:30 AM (04:00 UTC)
# ------------------------------------------------------------------------------
resource "azurerm_automation_schedule" "start" {
  count = var.enable_scheduling ? 1 : 0

  name                    = "${var.name_prefix}-start-schedule"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  start_time              = timeadd(timestamp(), "24h")
  description             = "Start GPU instances at IST 9:30 AM (04:00 UTC)"

  lifecycle {
    ignore_changes = [start_time]
  }
}

# ------------------------------------------------------------------------------
# Schedule for Stop VMSS - Ethiopia Time 6:00 PM (15:00 UTC)
# ------------------------------------------------------------------------------
resource "azurerm_automation_schedule" "stop" {
  count = var.enable_scheduling ? 1 : 0

  name                    = "${var.name_prefix}-stop-schedule"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  start_time              = timeadd(timestamp(), "24h")
  description             = "Stop GPU instances at Ethiopia Time 6:00 PM (15:00 UTC)"

  lifecycle {
    ignore_changes = [start_time]
  }
}

# ------------------------------------------------------------------------------
# Link Schedules to Runbooks
# ------------------------------------------------------------------------------
resource "azurerm_automation_job_schedule" "start" {
  count = var.enable_scheduling ? 1 : 0

  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main[0].name
  schedule_name           = azurerm_automation_schedule.start[0].name
  runbook_name            = azurerm_automation_runbook.start_vmss[0].name
}

resource "azurerm_automation_job_schedule" "stop" {
  count = var.enable_scheduling ? 1 : 0

  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main[0].name
  schedule_name           = azurerm_automation_schedule.stop[0].name
  runbook_name            = azurerm_automation_runbook.stop_vmss[0].name
}

# ------------------------------------------------------------------------------
# Diagnostic Settings for Automation Account
# ------------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "automation" {
  count = var.enable_scheduling ? 1 : 0

  name                       = "${var.name_prefix}-automation-diag"
  target_resource_id         = azurerm_automation_account.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "JobLogs"
  }

  enabled_log {
    category = "JobStreams"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
