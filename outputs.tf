
output "backend_url" {
  description = "The URL of the backend Cloud Run service that requires authentication to access and will return a 403 Error: Forbidden from Cloud Run"
  value       = google_cloud_run_v2_service.backend.uri
}

output "envoy_url" {
  description = "The URL of the Envoy Proxy Cloud Run service that will forward requests to the backend service and allow anonymous access to the backend service returning a 200 OK"
  value       = "${google_cloud_run_v2_service.envoy.uri}/backend"
}