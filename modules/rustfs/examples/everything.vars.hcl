# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A pinned image, a user, the console on a host network, metrics and traces
# to a collector, and an extra setting.
image_digest    = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
user            = "10001"
console_enabled = true
host_network    = "storage"
metrics_enabled = true
traces_enabled  = true
otlp_endpoint   = "http://otel.example.com:4318/"
extra_env       = { RUSTFS_COMPRESS_ENABLE = "true" }
node_pool       = "storage"
