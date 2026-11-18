# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "postgres"
  version     = "0.4.0"
  description = "A single PostgreSQL server (PostgreSQL License, official image, referenced, never shipped): data on a host volume, superuser, application databases and a pg_monitor user from the built-in secret store, health checks with roles, optional TLS with Norca's workload certificates, optional periodic pg_dumpall to S3 (RustFS)."
  url         = "https://www.postgresql.org"

  requires {
    norca = ">= 0.1.0"
  }
}
