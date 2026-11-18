# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three gateways on distinct nodes, Envoy in a container on the host
# network, with metrics on a fixed port and tags on the service.
job_type           = "service"
count              = 3
network_mode       = "host"
envoy_task_enabled = true
metrics_enabled    = true
metrics_port       = 9102
service_tags       = ["region-eu"]
node_pool          = "edge"
