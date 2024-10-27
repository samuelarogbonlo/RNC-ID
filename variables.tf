# Variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "node-guardians"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "node-guardians"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "docker.io/nginx:latest"
}

variable "db_instance_name" {
  description = "Name of the Cloud SQL instance"
  type        = string
  default     = "pgadmin"
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "pgadmin"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "value"
}

# Outputs
output "cloud_run_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.default.status[0].url
}

output "load_balancer_ip" {
  description = "The IP address of the load balancer"
  value       = google_compute_global_address.default.address
}

output "database_connection" {
  description = "The connection name of the database"
  value       = google_sql_database_instance.main.connection_name
  sensitive   = true
}
