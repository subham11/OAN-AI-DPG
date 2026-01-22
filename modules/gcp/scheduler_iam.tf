# ==============================================================================
# GCP Scheduler IAM - Service Account and Permissions
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
