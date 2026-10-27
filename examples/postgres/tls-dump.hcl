# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# TLS with the workload certificate of Norca's native mTLS (app mode), only
# TLS connections over TCP, and a nightly pg_dumpall into the bucket
# postgres-dump of the RustFS of the rustfs pack (service "rustfs" in the
# same namespace; create the bucket with its buckets variable).
#   norca secret put postgres/dump-storage access_key=<access key> secret_key=-
#   norca pack run postgres --registry=norca -f examples/postgres/tls-dump.hcl
tls_mode     = "mtls"
tls_required = true

dump_enabled = true
dump_cron    = "15 1 * * *"
dump_bucket  = "postgres-dump"

resources = {
  cpu    = 1000
  memory = 2048
}
