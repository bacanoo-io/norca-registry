# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Envoy installed on the nodes, run with raw_exec in host networking (no
# container runtime on the gateway nodes).
#   norca rigger install ./modules/mtls-gateway -name mtls-gateway -f modules/mtls-gateway/examples/envoy-binary.vars.hcl
network_mode       = "host"
envoy_task_enabled = true
envoy_driver       = "raw_exec"
envoy_binary       = "/usr/local/bin/envoy"
