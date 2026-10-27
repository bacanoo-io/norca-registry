# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://opentelemetry.io/docs/collector/"
}

pack {
  name        = "otel-collector"
  description = "The OpenTelemetry Collector (contrib, Apache-2.0) on every node as a system job: host metrics, the metrics of the Norca agent, NATS, Forgejo, the mTLS gateway, Consul and PostgreSQL found through the native catalog, an OTLP receiver for the applications on the node, everything exported to OpenObserve with the ingest credentials of the secret store over TLS trusting Norca's CA."
  version     = "0.1.1"

  requires {
    norca = ">= 0.1.0"
  }
}

variables_schema = file("values.schema.json")
