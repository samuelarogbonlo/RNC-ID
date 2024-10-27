
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
  default     = "ghcr.io/stefanprodan/podinfo:6.7.1"
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
output "load_balancer_ip" {
  value = google_compute_global_address.default.address
}


