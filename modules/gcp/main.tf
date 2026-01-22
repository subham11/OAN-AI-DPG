# ==============================================================================
# GCP Module - Main Entry Point
# ==============================================================================

locals {
  # Network name
  network_name = "${var.name_prefix}-vpc"

  # Startup script for instances
  startup_script = templatefile("${path.module}/templates/startup_script.sh.tpl", {
    nvidia_driver_version = var.nvidia_driver_version
    cuda_version          = var.cuda_version
    health_check_port     = var.health_check_port
    environment           = var.environment
  })
}

# ------------------------------------------------------------------------------
# Enable Required APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudscheduler" {
  count              = var.enable_scheduling ? 1 : 0
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudfunctions" {
  count              = var.enable_scheduling ? 1 : 0
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}
