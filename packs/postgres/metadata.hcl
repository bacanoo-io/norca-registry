# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://www.postgresql.org"
}

pack {
  name        = "postgres"
  description = "A single PostgreSQL server (PostgreSQL License, official image, referenced, never shipped): data on a host volume, superuser, application databases and a pg_monitor user from the built-in secret store, health checks with roles, optional TLS with Norca's workload certificates, optional periodic pg_dumpall to S3 (RustFS)."
  version     = "0.1.0"

  requires {
    norca = ">= 0.1.0"
  }
}

variables_schema = file("values.schema.json")
