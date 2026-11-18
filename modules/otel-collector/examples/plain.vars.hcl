# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# OpenObserve over plain HTTP, PostgreSQL with TLS but unverified, the
# metrics of other components off, OTLP on other ports.
openobserve_tls              = "none"
postgres_tls                 = "require"
forgejo_metrics_enabled      = false
consul_metrics_enabled       = false
nats_metrics_enabled         = false
mtls_gateway_metrics_enabled = true
discovery_namespaces         = ["default", "edge"]
otlp_grpc_port               = 14317
otlp_http_port               = 14318
