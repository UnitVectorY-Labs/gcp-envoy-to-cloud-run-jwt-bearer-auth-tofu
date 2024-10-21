variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources"
  type        = string
  default     = "us-east1"
}

variable "app_name" {
  description = "Name of the application used to prefix resources"
  type        = string
  default     = "envoytest"

  validation {
    condition     = length(var.app_name) >= 1 && length(var.app_name) <= 20 && can(regex("^[a-zA-Z0-9-]+$", var.app_name))
    error_message = "The app_name must be between 1 and 20 characters long and can only contain alphanumeric characters and dashes."
  }
}

variable "repository_url" {
  description = "Public Docker repository URL to pull images from (Default: ghcr.io)"
  type        = string
  default     = "https://ghcr.io"
}

variable "envoy_proxy_version" {
  description = "Envoy Proxy version to deploy; matches the tag of the Docker image"
  type        = string
  default     = "v1.31.2"
}

variable "authzjwtbearerinjector_version" {
  description = "authzjwtbearerinjector version to deploy; matches the tag of the Docker image"
  type        = string
  default     = "v0.2.0"
}

variable "backend_image" {
  description = "Docker image name to deploy to the backend in the format of <repository>/<image>:<tag>"
  type        = string
  default     = "unitvectory-labs/hellorest:v1"
}