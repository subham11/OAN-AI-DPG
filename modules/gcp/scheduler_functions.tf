# ==============================================================================
# GCP Cloud Functions - Start/Stop Instance Functions
# ==============================================================================

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
