# ==============================================================================
# GCP Cloud Scheduler Jobs - Cron Jobs for Start/Stop
# ==============================================================================

# ------------------------------------------------------------------------------
# Cloud Scheduler Jobs
# ------------------------------------------------------------------------------

# Start instances - IST 9:30 AM (04:00 UTC)
resource "google_cloud_scheduler_job" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  name        = "${var.name_prefix}-start-instances"
  description = "Start GPU instances at IST 9:30 AM (04:00 UTC)"
  schedule    = "0 4 * * 1-5" # 04:00 UTC, Mon-Fri
  time_zone   = "UTC"
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.start_instances[0].service_config[0].uri

    oidc_token {
      service_account_email = google_service_account.scheduler[0].email
    }
  }

  retry_config {
    retry_count          = 3
    max_retry_duration   = "60s"
    min_backoff_duration = "5s"
    max_backoff_duration = "30s"
  }

  depends_on = [
    google_project_service.cloudscheduler
  ]
}

# Stop instances - Ethiopia Time 6:00 PM (15:00 UTC)
resource "google_cloud_scheduler_job" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  name        = "${var.name_prefix}-stop-instances"
  description = "Stop GPU instances at Ethiopia Time 6:00 PM (15:00 UTC)"
  schedule    = "0 15 * * 1-5" # 15:00 UTC, Mon-Fri
  time_zone   = "UTC"
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.stop_instances[0].service_config[0].uri

    oidc_token {
      service_account_email = google_service_account.scheduler[0].email
    }
  }

  retry_config {
    retry_count          = 3
    max_retry_duration   = "60s"
    min_backoff_duration = "5s"
    max_backoff_duration = "30s"
  }

  depends_on = [
    google_project_service.cloudscheduler
  ]
}
