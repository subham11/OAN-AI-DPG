# ==============================================================================
# GCP Scheduler Monitoring - Log-based Alerts for Function Errors
# ==============================================================================

# ------------------------------------------------------------------------------
# Log-based Metric for Function Errors
# ------------------------------------------------------------------------------
resource "google_logging_metric" "function_errors" {
  count = var.enable_scheduling ? 1 : 0

  name   = "${var.name_prefix}-function-errors"
  filter = <<-EOT
    resource.type="cloud_function" 
    AND resource.labels.function_name=~"${var.name_prefix}-(start|stop)-instances"
    AND severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# ------------------------------------------------------------------------------
# Alert Policy for Function Errors
# ------------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_scheduling ? 1 : 0

  display_name = "${var.name_prefix}-scheduler-errors"
  combiner     = "OR"

  conditions {
    display_name = "Scheduler Function Errors"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.function_errors[0].name}\" AND resource.type=\"cloud_function\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "GPU instance scheduler function reported errors"
    mime_type = "text/markdown"
  }
}
