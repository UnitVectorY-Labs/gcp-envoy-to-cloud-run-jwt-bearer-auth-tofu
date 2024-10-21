
# Artifact Registry needed for Deployments

resource "google_artifact_registry_repository" "dockerhub" {
  location      = var.region
  project       = var.project_id
  repository_id = "${var.app_name}-docker"
  description   = "Proxy Container Registry for ${var.app_name} for Docker Hub"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }
}

resource "google_artifact_registry_repository" "ghcr" {
  location      = var.region
  project       = var.project_id
  repository_id = "${var.app_name}-ghcr"
  description   = "Proxy Container Registry for ${var.app_name}"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    docker_repository {
      custom_repository {
        uri = "https://ghcr.io"
      }
    }
  }
}

resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  project       = var.project_id
  repository_id = "${var.app_name}-repo"
  description   = "Proxy Container Registry for ${var.app_name}"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    docker_repository {
      custom_repository {
        uri = var.repository_url
      }
    }
  }
}

# Create a bucket for the backend

resource "random_uuid" "bucket_suffix" {
  # Generate a random UUID to append to the bucket name to ensure uniqueness
}

resource "google_storage_bucket" "config" {
  project  = var.project_id
  location = var.region
  name     = "${var.app_name}-config-${random_uuid.bucket_suffix.result}"
}

# The Service Accounts used by Cloud Run

resource "google_service_account" "envoy" {
  project      = var.project_id
  account_id   = "${var.app_name}-envoy-sa"
  display_name = "${var.app_name} Service Account for EnvoyProxy"
}

resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "${var.app_name}-backend-sa"
  display_name = "${var.app_name} Service Account for Backend"
}

resource "google_service_account" "access" {
  project      = var.project_id
  account_id   = "${var.app_name}-access-sa"
  display_name = "${var.app_name} Service Account for Accessing Backend"
}

# Create the Key for the Access Service Account

resource "google_service_account_key" "access" {
  service_account_id = google_service_account.access.name
  key_algorithm      = "KEY_ALG_RSA_2048"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

# Grant the Service Accounts the necessary permissions

resource "google_storage_bucket_iam_member" "envoy_read_bucket" {
  # Grant the Cloud Run Service Account for Envoy Read permissions 
  # to the bucket where the configuration is stored
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.envoy.email}"
}

resource "google_secret_manager_secret_iam_member" "envoy_read_secret" {
  # Grant the Cloud Run Service Account for Envoy Read permissions 
  # to the secret where the configuration is stored
  project   = var.project_id
  secret_id = google_secret_manager_secret.authzjwtbearerinjector.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.envoy.email}"
}

resource "google_cloud_run_service_iam_member" "access_invoke_backend" {
  # Grant the access Service Account the necessary permissions 
  # to invoke the Backend service in Cloud Run
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.access.email}"
}

resource "google_cloud_run_service_iam_member" "envoy_anonymous_access" {
  # Allow Anonymous Access to the Envoy Proxy Service
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_v2_service.envoy.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create the Configuration for the Envoy Proxy from the Template

locals {
  envoy_config = templatefile("${path.module}/envoy-template.yaml", {
    # EnvoyProxy needs to know the URL of the backend service from Cloud Run
    BACKEND_DOMAIN = trimprefix(google_cloud_run_v2_service.backend.uri, "https://")
  })

  # Decode the Service Account Key to use in the configuration
  access_key_json = jsondecode(base64decode(google_service_account_key.access.private_key))

  authzjwtbearerinjector_config = templatefile("${path.module}/authzjwtbearerinjector-template.yaml", {
    # The private key is a multiline YAML parameter therefore needs to be indented
    SERVICE_ACCOUNT_PRIVATE_KEY = replace(local.access_key_json.private_key, "\n", "\n  "),
    SERVICE_ACCOUNT_KEY_ID      = local.access_key_json.private_key_id,
    SERVICE_ACCOUNT_EMAIL       = google_service_account.access.email
  })

  # We use a hash of the template to trigger a redeployment when the template changes
  envoy_config_hash = sha256(local.envoy_config)
}

resource "google_storage_bucket_object" "envoy_config" {
  # Store the configuration in a bucket to be read by the Envoy Proxy
  name    = "envoy.yaml"
  bucket  = google_storage_bucket.config.name
  content = local.envoy_config
}

resource "google_secret_manager_secret" "authzjwtbearerinjector" {
  project   = var.project_id
  secret_id = "${var.app_name}-authzjwtbearerinjector-config"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "authzjwtbearerinjector" {
  # The authzjwtbearerinjector configuration contains a private key
  # and is stored as a secret
  secret      = google_secret_manager_secret.authzjwtbearerinjector.id
  secret_data = local.authzjwtbearerinjector_config
}

# Deploy the Cloud Run Services (EnvoyProxy and Backend)

resource "google_cloud_run_v2_service" "envoy" {
  name     = "${var.app_name}-envoy"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  template {
    service_account = google_service_account.envoy.email

    volumes {
      name = "envoy-config"
      gcs {
        bucket    = google_storage_bucket.config.name
        read_only = true
      }
    }

    volumes {
      name = "authzjwtbearerinjector-config"
      secret {
        secret       = google_secret_manager_secret.authzjwtbearerinjector.secret_id
        default_mode = 292 # 0444 (read only)
        items {
          version = google_secret_manager_secret_version.authzjwtbearerinjector.version
          path    = "config.yaml"
        }
      }
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}-docker/envoyproxy/envoy:${var.envoy_proxy_version}"

      ports {
        container_port = 8080
      }

      volume_mounts {
        # Mount the configuration from the bucket
        name       = "envoy-config"
        mount_path = "/mnt/config"
      }

      # Tell Envoy to use the configuration file
      args = [
        "-c",
        "/mnt/config/envoy.yaml"
      ]

      # Trigger a redeployment when the configuration changes
      env {
        name  = "CONFIG_HASH"
        value = local.envoy_config_hash
      }
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}-ghcr/unitvectory-labs/authzjwtbearerinjector:${var.authzjwtbearerinjector_version}"

      resources {
        limits = {
          # Sidecar needs minimal resources
          cpu    = "1"
          memory = "128Mi"
        }
      }

      volume_mounts {
        # Mount the configuration from the secret
        name       = "authzjwtbearerinjector-config"
        mount_path = "/mnt/authzjwtbearerinjector/"
      }

      env {
        # Use the configuration file from the secret manager
        name  = "CONFIG_FILE_PATH"
        value = "/mnt/authzjwtbearerinjector/config.yaml"
      }
    }
  }

  depends_on = [
    google_artifact_registry_repository.dockerhub,
    google_artifact_registry_repository.ghcr,
  ]
}

resource "google_cloud_run_v2_service" "backend" {
  name     = "${var.app_name}-backend"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  template {
    service_account = google_service_account.backend.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}-repo/${var.backend_image}"

      ports {
        container_port = 8080
      }
    }
  }

  depends_on = [
    google_artifact_registry_repository.repo,
  ]
}