# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# OTLP mode: the agents push their telemetry to 127.0.0.1:4317 of their node
# (telemetry { otlp {} } in the agent configuration, Prometheus off there);
# the collector does not scrape them. The catalog is still read through the
# agent's HTTPS API.
nomad_otlp_enabled   = true
nomad_address        = "https://127.0.0.1:4646"
nomad_ca_secret_path = "norca/agent-ca"
discovery_namespaces = ["default", "observability"]
