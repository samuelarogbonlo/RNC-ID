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
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Cloud SQL Instance (PostgreSQL)
resource "google_sql_database_instance" "main" {
  name             = var.db_instance_name
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier = "db-f1-micro"
    edition = "ENTERPRISE" 

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled     = true
      start_time  = "02:00"
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
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    username = google_sql_user.user.name
    password = random_password.db_password.result
    database = google_sql_database.database.name
    instance = google_sql_database_instance.main.connection_name
  })
}

# VPC Access Connector for Cloud Run
resource "google_vpc_access_connector" "connector" {
  name          = "${var.project_name}-connector"
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = "10.8.0.0/28" 
  
#   # Specify machine type (optional)
#   machine_type = "e2-micro"
  
  # Minimum and maximum instances (optional)
  min_instances = 2
  max_instances = 3
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
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.id
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true
}

# IAM - Allow unauthenticated access to Cloud Run
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_service.default.location
  service  = google_cloud_run_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Reserve a global IP address
resource "google_compute_global_address" "default" {
  name = "${var.project_name}-lb-ip"
}

# URL Map
resource "google_compute_url_map" "default" {
  name            = "${var.project_name}-url-map"
  default_service = google_compute_backend_service.default.id
}

# Backend Service
resource "google_compute_backend_service" "default" {
  name                  = "${var.project_name}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30

  backend {
    group = google_compute_region_network_endpoint_group.cloudrun_neg.id
  }
}

# Target HTTP Proxy
resource "google_compute_target_http_proxy" "default" {
  name    = "${var.project_name}-http-proxy"
  url_map = google_compute_url_map.default.id
}

# Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "default" {
  name       = "${var.project_name}-lb-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_address = google_compute_global_address.default.id
}

# Cloud Run Network Endpoint Group
resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
  name                  = "${var.project_name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.default.name
  }
}
