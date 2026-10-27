# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Envoy installed on the nodes, run with raw_exec in host networking (no
# container runtime on the gateway nodes).
#   norca pack run mtls-gateway --registry=norca -f examples/mtls-gateway/envoy-binary.hcl
network_mode       = "host"
envoy_task_enabled = true
envoy_driver       = "raw_exec"
envoy_binary       = "/usr/local/bin/envoy"
