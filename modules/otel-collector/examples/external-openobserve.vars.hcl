# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A minimal collector: host metrics, the Norca agent and OTLP of the
# applications, exported to an OpenObserve outside the cluster with a public
# certificate; no catalog discovery, no PostgreSQL.
#   norca rigger install ./modules/otel-collector -name otel-collector -f modules/otel-collector/examples/external-openobserve.vars.hcl
openobserve_endpoint     = "https://observe.example.com"
openobserve_tls          = "system"
openobserve_server_name  = "observe.example.com"
openobserve_organization = "platform"
discovery_namespaces     = []
postgres_metrics_enabled = false
