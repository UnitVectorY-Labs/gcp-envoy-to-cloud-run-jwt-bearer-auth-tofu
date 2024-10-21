# gcp-envoy-to-cloud-run-jwt-bearer-auth-tofu

Demonstrates how to configure EnvoyProxy running on Cloud Run to authenticate to a backend service, using jwt-bearer flow through ExtAuthz with authzjwtbearerinjector.

## Overview

This sample project demonstrates how to configure [EnvoyProxy](https://www.envoyproxy.io/) on [Cloud Run](https://cloud.google.com/run) to authenticate to a backend service using the [jwt-bearer](https://datatracker.ietf.org/doc/html/rfc7523) flow with [ExtAuthz](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ext_authz/v3/ext_authz.proto), utilizing [authzjwtbearerinjector](https://github.com/UnitVectorY-Labs/authzjwtbearerinjector) for service-to-service authentication. The solution can be fully deployed using Terraform/OpenTofu.

The primary goal is to showcase how EnvoyProxy can authenticate to a backend service using a private key, rather than directly using the service account of the Cloud Run service (the best practice for GCP environments). For the best-practice approach, refer to [gcp-envoy-to-cloud-run-metadata-auth-tofu](https://github.com/UnitVectorY-Labs/gcp-envoy-to-cloud-run-metadata-auth-tofu), which utilizes the Cloud Run service account without authzjwtbearerinjector.

This project uses a private key directly to demonstrate how authzjwtbearerinjector can be applied in scenarios where non-GCP services need to be accessed, or where GCP resources are accessed using a service account outside of GCP.
