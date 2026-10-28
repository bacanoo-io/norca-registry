# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://openobserve.ai"
}

pack {
  name        = "openobserve"
  description = "OpenObserve (AGPL-3.0, referenced, never shipped) as the observability backend (logs, metrics, traces) of a Norca cluster: a single node on a host volume (SQLite) or a cluster with router, ingester, querier, compactor and alertmanager groups (PostgreSQL, NATS, RustFS), TLS with Norca's workload certificates, root user from the built-in secret store, an ingest service account for the collectors."
  version     = "0.2.0"

  requires {
    norca = ">= 0.1.0"
  }
}
