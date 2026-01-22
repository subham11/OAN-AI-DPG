# ==============================================================================
# GCP Global HTTPS Load Balancer
# ==============================================================================

# ------------------------------------------------------------------------------
# Global Static IP
# ------------------------------------------------------------------------------
resource "google_compute_global_address" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  name = "${var.name_prefix}-lb-ip"
}

# ------------------------------------------------------------------------------
# Health Check for Load Balancer
# ------------------------------------------------------------------------------
resource "google_compute_health_check" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  name                = "${var.name_prefix}-lb-hc"
  check_interval_sec  = var.health_check_interval
  timeout_sec         = 10
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold

  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }

  log_config {
    enable = true
  }
}

# ------------------------------------------------------------------------------
# Backend Service
# ------------------------------------------------------------------------------
resource "google_compute_backend_service" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name                  = "${var.name_prefix}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.lb[0].id]
  load_balancing_scheme = "EXTERNAL"

  backend {
    group           = google_compute_region_instance_group_manager.gpu.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  connection_draining_timeout_sec = 30
}

# ------------------------------------------------------------------------------
# URL Map
# ------------------------------------------------------------------------------
resource "google_compute_url_map" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name            = "${var.name_prefix}-url-map"
  default_service = google_compute_backend_service.main[0].id
}

# ------------------------------------------------------------------------------
# HTTP Proxy
# ------------------------------------------------------------------------------
resource "google_compute_target_http_proxy" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name    = "${var.name_prefix}-http-proxy"
  url_map = google_compute_url_map.main[0].id
}

# ------------------------------------------------------------------------------
# HTTP Forwarding Rule
# ------------------------------------------------------------------------------
resource "google_compute_global_forwarding_rule" "http" {
  count = var.enable_load_balancer ? 1 : 0

  name                  = "${var.name_prefix}-http-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.main[0].id
  ip_address            = google_compute_global_address.lb[0].id
}

# ------------------------------------------------------------------------------
# HTTPS (Optional - requires SSL certificate)
# ------------------------------------------------------------------------------
# Uncomment when SSL certificate is available

# resource "google_compute_managed_ssl_certificate" "main" {
#   count = var.enable_load_balancer ? 1 : 0
#
#   name = "${var.name_prefix}-ssl-cert"
#
#   managed {
#     domains = ["your-domain.com"]
#   }
# }

# resource "google_compute_target_https_proxy" "main" {
#   count = var.enable_load_balancer ? 1 : 0
#
#   name             = "${var.name_prefix}-https-proxy"
#   url_map          = google_compute_url_map.main[0].id
#   ssl_certificates = [google_compute_managed_ssl_certificate.main[0].id]
# }

# resource "google_compute_global_forwarding_rule" "https" {
#   count = var.enable_load_balancer ? 1 : 0
#
#   name                  = "${var.name_prefix}-https-rule"
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "EXTERNAL"
#   port_range            = "443"
#   target                = google_compute_target_https_proxy.main[0].id
#   ip_address            = google_compute_global_address.lb[0].id
# }

# ------------------------------------------------------------------------------
# Cloud Armor Security Policy (Optional)
# ------------------------------------------------------------------------------
resource "google_compute_security_policy" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name = "${var.name_prefix}-security-policy"

  # Default rule - allow all
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 1000
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate limiting rule"
  }
}

# ------------------------------------------------------------------------------
# Monitoring Dashboard for Load Balancer
# ------------------------------------------------------------------------------
resource "google_monitoring_dashboard" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} Load Balancer Dashboard"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Request Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\""
                }
              }
            }]
          }
        },
        {
          title = "Latency"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/total_latencies\""
                }
              }
            }]
          }
        },
        {
          title = "Backend Latency"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\""
                }
              }
            }]
          }
        },
        {
          title = "Error Rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND metric.labels.response_code_class!=\"200\""
                }
              }
            }]
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.monitoring]
}
