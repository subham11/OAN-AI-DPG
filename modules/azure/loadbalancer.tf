# ==============================================================================
# Azure Load Balancer Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Public IP for Load Balancer
# ------------------------------------------------------------------------------
resource "azurerm_public_ip" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  name                = "${var.name_prefix}-lb-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.name_prefix}-lb"

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Load Balancer
# ------------------------------------------------------------------------------
resource "azurerm_lb" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name                = "${var.name_prefix}-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb[0].id
  }

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Backend Address Pool
# ------------------------------------------------------------------------------
resource "azurerm_lb_backend_address_pool" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name            = "${var.name_prefix}-backend-pool"
  loadbalancer_id = azurerm_lb.main[0].id
}

# ------------------------------------------------------------------------------
# Health Probe
# ------------------------------------------------------------------------------
resource "azurerm_lb_probe" "health" {
  count = var.enable_load_balancer ? 1 : 0

  name                = "${var.name_prefix}-health-probe"
  loadbalancer_id     = azurerm_lb.main[0].id
  protocol            = "Http"
  port                = var.health_check_port
  request_path        = var.health_check_path
  interval_in_seconds = var.health_check_interval
  number_of_probes    = var.unhealthy_threshold
}

# ------------------------------------------------------------------------------
# Load Balancer Rules
# ------------------------------------------------------------------------------

# HTTP Rule
resource "azurerm_lb_rule" "http" {
  count = var.enable_load_balancer ? 1 : 0

  name                           = "HTTP"
  loadbalancer_id                = azurerm_lb.main[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = var.app_port
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main[0].id]
  probe_id                       = azurerm_lb_probe.health[0].id
  idle_timeout_in_minutes        = 4
  enable_tcp_reset               = true
}

# HTTPS Rule (if needed)
resource "azurerm_lb_rule" "https" {
  count = var.enable_load_balancer ? 1 : 0

  name                           = "HTTPS"
  loadbalancer_id                = azurerm_lb.main[0].id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = var.app_port
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main[0].id]
  probe_id                       = azurerm_lb_probe.health[0].id
  idle_timeout_in_minutes        = 4
  enable_tcp_reset               = true
}

# ------------------------------------------------------------------------------
# Load Balancer Diagnostic Settings
# ------------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  name                       = "${var.name_prefix}-lb-diag"
  target_resource_id         = azurerm_lb.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ------------------------------------------------------------------------------
# Alerts for Load Balancer
# ------------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "lb_health" {
  count = var.enable_load_balancer ? 1 : 0

  name                = "${var.name_prefix}-lb-health-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_lb.main[0].id]
  description         = "Alert when load balancer health probe fails"
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.Network/loadBalancers"
    metric_name      = "DipAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  tags = var.common_tags
}
