# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One RustFS server that pushes its metrics over OTLP/HTTP to the
# OpenTelemetry Collector of the otel-collector pack on its node.
#   norca pack run rustfs --registry=norca -f examples/rustfs/metrics.hcl
buckets         = ["norca-backup", "openobserve"]
metrics_enabled = true
