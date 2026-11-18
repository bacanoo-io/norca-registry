# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# OpenObserve behind a CA of the secret store, an organization of its own,
# the agent over HTTPS with its CA, PostgreSQL verified against the mTLS
# bundle, no OTLP, no root file system of the host and no discovery.
openobserve_tls            = "secret"
openobserve_ca_secret_path = "openobserve/ca"
openobserve_server_name    = "o2.example.com"
openobserve_organization   = "platform"
otlp_enabled               = false
host_root_volume           = ""
nomad_address              = "https://127.0.0.1:4646"
nomad_ca_secret_path       = "norca/ca"
discovery_namespaces       = []
postgres_tls               = "verify-ca"
self_metrics_enabled       = false
host_network               = "private"
