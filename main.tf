
# VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

# Subnets
resource "google_compute_subnetwork" "private" {
  name          = "${var.project_name}-private-subnet"
  ip_cidr_range = "10.0.0.0/20"
  network       = google_compute_network.main.id
  region        = var.region

  # Enable private Google Access for Cloud Run
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.1.0.0/20"
  }

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.project_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

# NAT configuration
resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_name}-nat"
  router                            = google_compute_router.router.name
  region                            = var.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Cloud SQL Instance (PostgreSQL)
resource "google_sql_database_instance" "main" {
  name             = var.db_instance_name
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier = "db-f1-micro"
    
    ip_configuration {
      ipv4_enabled       = false
      private_network    = google_compute_network.main.id
    }

    backup_configuration {
      enabled            = true
      start_time        = "02:00"
    }

    database_flags {
      name  = "max_connections"
      value = "1000"
    }
  }

  deletion_protection = true
}

# Cloud SQL Database
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

# Cloud SQL User
resource "google_sql_user" "user" {
  name     = var.db_user
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# Random password for database
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()_+"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

# Secret Manager for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "${var.project_name}-db-credentials"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id

  secret_data = jsonencode({
    username = google_sql_user.user.name
    password = random_password.db_password.result
    database = google_sql_database.database.name
    instance = google_sql_database_instance.main.connection_name
  })
}

# Cloud Run service
resource "google_cloud_run_service" "default" {
  name     = "${var.project_name}-service"
  location = var.region

  template {
    spec {
      containers {
        image = var.container_image
        
        env {
          name = "DB_USER"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_credentials.secret_id
              key  = "username"
            }
          }
        }
        
        env {
          name = "DB_PASS"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_credentials.secret_id
              key  = "password"
            }
          }
        }

        env {
          name = "DB_NAME"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_credentials.secret_id
              key  = "database"
            }
          }
        }

        env {
          name = "INSTANCE_CONNECTION_NAME"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_credentials.secret_id
              key  = "instance"
            }
          }
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = "10"
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.main.connection_name
        "run.googleapis.com/client-name"        = "terraform"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true
}

# Load Balancer
resource "google_compute_global_address" "default" {
  name = "${var.project_name}-lb-ip"
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "${var.project_name}-lb-forwarding-rule"
  target                = google_compute_target_https_proxy.default.id
  port_range           = "443"
  ip_address           = google_compute_global_address.default.id
}

resource "google_compute_managed_ssl_certificate" "default" {
  name = "${var.project_name}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_target_https_proxy" "default" {
  name             = "${var.project_name}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

resource "google_compute_url_map" "default" {
  name            = "${var.project_name}-url-map"
  default_service = google_compute_backend_service.default.id
}

resource "google_compute_backend_service" "default" {
  name                  = "${var.project_name}-backend"
  protocol              = "HTTP"
  port_name            = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec          = 30

  backend {
    group = google_compute_region_network_endpoint_group.cloudrun_neg.id
  }
}

resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
  name                  = "${var.project_name}-neg"
  network_endpoint_type = "SERVERLESS"
  region               = var.region
  
  cloud_run {
    service = google_cloud_run_service.default.name
  }
}

# IAM - Allow unauthenticated access to Cloud Run
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_service.default.location
  service  = google_cloud_run_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

