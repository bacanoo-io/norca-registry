# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Two gateways (a service job) with an Envoy task defined by the pack: a
# pinned image from an internal mirror, more resources than the injected task.
#   norca pack run mtls-gateway --registry=norca -f examples/mtls-gateway/envoy-image.hcl
job_type = "service"
count    = 2

envoy_task_enabled = true
envoy_driver       = "docker"
envoy_image        = "registry.internal:5000/envoyproxy/envoy:v1.40.1"
envoy_log_level    = "warning"

envoy_resources = {
  cpu    = 250
  memory = 256
}

# The statistics of Envoy (/stats/prometheus) for the otel-collector pack.
metrics_enabled = true
