# ==============================================================================
# GCP Networking Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# VPC Network
# ------------------------------------------------------------------------------
resource "google_compute_network" "main" {
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.compute]
}

# ------------------------------------------------------------------------------
# Public Subnets
# ------------------------------------------------------------------------------
resource "google_compute_subnetwork" "public" {
  count = length(var.public_subnet_cidrs)

  name                     = "${var.name_prefix}-public-${count.index + 1}"
  ip_cidr_range            = var.public_subnet_cidrs[count.index]
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ------------------------------------------------------------------------------
# Private Subnets
# ------------------------------------------------------------------------------
resource "google_compute_subnetwork" "private" {
  count = length(var.private_subnet_cidrs)

  name                     = "${var.name_prefix}-private-${count.index + 1}"
  ip_cidr_range            = var.private_subnet_cidrs[count.index]
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ------------------------------------------------------------------------------
# Cloud Router for NAT
# ------------------------------------------------------------------------------
resource "google_compute_router" "main" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

# ------------------------------------------------------------------------------
# Cloud NAT for Private Subnets
# ------------------------------------------------------------------------------
resource "google_compute_router_nat" "main" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                    = subnetwork.value.id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ------------------------------------------------------------------------------
# Firewall Rules
# ------------------------------------------------------------------------------

# Allow SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.name_prefix}-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = ["gpu-instance"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow HTTP
resource "google_compute_firewall" "allow_http" {
  name    = "${var.name_prefix}-allow-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = var.allowed_http_cidrs
  target_tags   = ["gpu-instance", "http-server"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow HTTPS
resource "google_compute_firewall" "allow_https" {
  name    = "${var.name_prefix}-allow-https"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = var.allowed_http_cidrs
  target_tags   = ["gpu-instance", "https-server"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow Health Checks (GCP Load Balancer ranges)
resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.name_prefix}-allow-health-check"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.health_check_port), tostring(var.app_port)]
  }

  # GCP health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gpu-instance"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow Internal Communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.name_prefix}-allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Deny all ingress (implicit, but explicit for logging)
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.name_prefix}-deny-all-ingress"
  network  = google_compute_network.main.name
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
