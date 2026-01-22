# ==============================================================================
# GCP Scheduler Resources - Cloud Scheduler + Cloud Functions
# ==============================================================================
# Scheduling: IST 9:30 AM (04:00 UTC) to Ethiopia Time 6:00 PM (15:00 UTC)
# ==============================================================================

# ------------------------------------------------------------------------------
# Service Account for Cloud Functions
# ------------------------------------------------------------------------------
resource "google_service_account" "scheduler" {
  count = var.enable_scheduling ? 1 : 0

  account_id   = "${var.name_prefix}-scheduler"
  display_name = "GPU Instance Scheduler Service Account"
}

# IAM - Allow managing compute instances
resource "google_project_iam_member" "scheduler_compute" {
  count = var.enable_scheduling ? 1 : 0

  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.scheduler[0].email}"
}

# IAM - Allow invoking Cloud Functions
resource "google_project_iam_member" "scheduler_invoker" {
  count = var.enable_scheduling ? 1 : 0

  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler[0].email}"
}

# ------------------------------------------------------------------------------
# Cloud Storage for Function Code
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "functions" {
  count = var.enable_scheduling ? 1 : 0

  name                        = "${var.project_id}-${var.name_prefix}-functions"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# ------------------------------------------------------------------------------
# Start Instances Function Code
# ------------------------------------------------------------------------------
data "archive_file" "start_function" {
  count = var.enable_scheduling ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/functions/start_instances.zip"

  source {
    content = templatefile("${path.module}/templates/start_instances.py.tpl", {
      project_id  = var.project_id
      region      = var.region
      mig_name    = google_compute_region_instance_group_manager.gpu.name
      target_size = var.asg_desired_capacity
    })
    filename = "main.py"
  }

  source {
    content  = "google-cloud-compute>=1.0.0"
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "start_function" {
  count = var.enable_scheduling ? 1 : 0

  name   = "start_instances_${data.archive_file.start_function[0].output_md5}.zip"
  bucket = google_storage_bucket.functions[0].name
  source = data.archive_file.start_function[0].output_path
}

# ------------------------------------------------------------------------------
# Stop Instances Function Code
# ------------------------------------------------------------------------------
data "archive_file" "stop_function" {
  count = var.enable_scheduling ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/functions/stop_instances.zip"

  source {
    content = templatefile("${path.module}/templates/stop_instances.py.tpl", {
      project_id = var.project_id
      region     = var.region
      mig_name   = google_compute_region_instance_group_manager.gpu.name
    })
    filename = "main.py"
  }

  source {
    content  = "google-cloud-compute>=1.0.0"
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "stop_function" {
  count = var.enable_scheduling ? 1 : 0

  name   = "stop_instances_${data.archive_file.stop_function[0].output_md5}.zip"
  bucket = google_storage_bucket.functions[0].name
  source = data.archive_file.stop_function[0].output_path
}

# ------------------------------------------------------------------------------
# Cloud Functions (2nd Gen)
# ------------------------------------------------------------------------------
resource "google_cloudfunctions2_function" "start_instances" {
  count = var.enable_scheduling ? 1 : 0

  name     = "${var.name_prefix}-start-instances"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "start_instances"
    source {
      storage_source {
        bucket = google_storage_bucket.functions[0].name
        object = google_storage_bucket_object.start_function[0].name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.scheduler[0].email

    environment_variables = {
      PROJECT_ID  = var.project_id
      REGION      = var.region
      MIG_NAME    = google_compute_region_instance_group_manager.gpu.name
      TARGET_SIZE = tostring(var.asg_desired_capacity)
      LOG_LEVEL   = "INFO"
    }
  }

  depends_on = [
    google_project_service.cloudfunctions
  ]
}

resource "google_cloudfunctions2_function" "stop_instances" {
  count = var.enable_scheduling ? 1 : 0

  name     = "${var.name_prefix}-stop-instances"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "stop_instances"
    source {
      storage_source {
        bucket = google_storage_bucket.functions[0].name
        object = google_storage_bucket_object.stop_function[0].name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.scheduler[0].email

    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      MIG_NAME   = google_compute_region_instance_group_manager.gpu.name
      LOG_LEVEL  = "INFO"
    }
  }

  depends_on = [
    google_project_service.cloudfunctions
  ]
}

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

# ------------------------------------------------------------------------------
# IAM for Cloud Scheduler to invoke Functions
# ------------------------------------------------------------------------------
resource "google_cloudfunctions2_function_iam_member" "start_invoker" {
  count = var.enable_scheduling ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.start_instances[0].name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.scheduler[0].email}"
}

resource "google_cloudfunctions2_function_iam_member" "stop_invoker" {
  count = var.enable_scheduling ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.stop_instances[0].name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.scheduler[0].email}"
}

# ------------------------------------------------------------------------------
# Log-based Alert for Function Errors
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
