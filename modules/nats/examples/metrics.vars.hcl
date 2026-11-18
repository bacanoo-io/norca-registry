# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three NATS servers with JetStream and the Prometheus exporter next to each
# of them (service nats-metrics, scraped by the otel-collector pack).
#   norca pack run nats --registry=norca --name=nats -f examples/nats/metrics.hcl
metrics_enabled = true
