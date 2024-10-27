# Variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "777310605028"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cresh-test"
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

variable "domain_name" {
  description = "Domain name for the load balancer"
  type        = string
  default     = "new-service"
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
