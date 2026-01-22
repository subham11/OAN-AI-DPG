# ==============================================================================
# GCP Compute Resources - Managed Instance Group
# ==============================================================================

# ------------------------------------------------------------------------------
# Service Account for Instances
# ------------------------------------------------------------------------------
resource "google_service_account" "instance" {
  account_id   = "${var.name_prefix}-sa"
  display_name = "GPU Instance Service Account"
}

resource "google_project_iam_member" "instance_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.instance.email}"
}

resource "google_project_iam_member" "instance_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.instance.email}"
}

# ------------------------------------------------------------------------------
# Instance Template
# ------------------------------------------------------------------------------
resource "google_compute_instance_template" "gpu" {
  name_prefix  = "${var.name_prefix}-gpu-"
  machine_type = var.machine_type
  region       = var.region

  tags = ["gpu-instance", "http-server", "https-server"]

  labels = merge(var.common_tags, {
    gpu_instance = "true"
  })

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.root_volume_size
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.private[0].id
  }

  # GPU Configuration
  guest_accelerator {
    type  = var.gpu_type
    count = var.gpu_count
  }

  # Required for GPU instances
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
    preemptible         = false
  }

  service_account {
    email  = google_service_account.instance.email
    scopes = ["cloud-platform"]
  }

  # Startup script
  metadata = {
    startup-script = local.startup_script
    ssh-keys       = var.ssh_public_key != "" ? "ubuntu:${var.ssh_public_key}" : null
  }

  # Shielded VM
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# Regional Managed Instance Group
# ------------------------------------------------------------------------------
resource "google_compute_region_instance_group_manager" "gpu" {
  name               = "${var.name_prefix}-gpu-mig"
  base_instance_name = "${var.name_prefix}-gpu"
  region             = var.region

  version {
    instance_template = google_compute_instance_template.gpu.id
  }

  target_size = var.asg_desired_capacity

  named_port {
    name = "http"
    port = var.app_port
  }

  named_port {
    name = "health"
    port = var.health_check_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.instance.id
    initial_delay_sec = 300
  }

  update_policy {
    type                           = "PROACTIVE"
    instance_redistribution_type   = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 1
    max_unavailable_fixed          = 0
    replacement_method             = "SUBSTITUTE"
  }

  lifecycle {
    ignore_changes = [target_size]
  }
}

# ------------------------------------------------------------------------------
# Health Check for Auto-Healing
# ------------------------------------------------------------------------------
resource "google_compute_health_check" "instance" {
  name                = "${var.name_prefix}-instance-hc"
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
# Auto-Scaler
# ------------------------------------------------------------------------------
resource "google_compute_region_autoscaler" "gpu" {
  name   = "${var.name_prefix}-gpu-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.gpu.id

  autoscaling_policy {
    min_replicas    = var.asg_min_size
    max_replicas    = var.asg_max_size
    cooldown_period = 300

    cpu_utilization {
      target = var.scale_up_cpu_threshold / 100
    }

    scale_in_control {
      max_scaled_in_replicas {
        fixed = 1
      }
      time_window_sec = 600
    }
  }
}

# ------------------------------------------------------------------------------
# Monitoring Alert Policies
# ------------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "cpu_high" {
  display_name = "${var.name_prefix}-cpu-high"
  combiner     = "OR"

  conditions {
    display_name = "CPU Utilization High"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.scale_up_cpu_threshold / 100

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "CPU utilization exceeded ${var.scale_up_cpu_threshold}%"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring]
}

resource "google_monitoring_alert_policy" "gpu_memory" {
  display_name = "${var.name_prefix}-gpu-memory"
  combiner     = "OR"

  conditions {
    display_name = "GPU Memory High"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/gpu/memory/bytes_used\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.9

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "GPU memory utilization exceeded 90%"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring]
}
