# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One RustFS server that pushes its metrics over OTLP/HTTP to the
# OpenTelemetry Collector of the otel-collector module on its node.
#   norca rigger install ./modules/rustfs -name rustfs -f modules/rustfs/examples/metrics.vars.hcl
buckets         = ["norca-backup", "openobserve"]
metrics_enabled = true
