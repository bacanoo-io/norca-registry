# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Cluster mode with TLS from a secret, ingesters on a host volume, the
# metadata in PostgreSQL by DSN, NATS and S3 at fixed endpoints, a bucket
# made elsewhere, two organizations.
mode                     = "cluster"
tls_mode                 = "secret"
tls_cert_domain          = "openobserve.internal"
ingester_host_volume     = "openobserve-wal"
postgres_dsn_secret_path = "openobserve/dsn"
nats_endpoints           = ["10.0.0.11:4222", "10.0.0.12:4222"]
nats_secret_path         = ""
s3_endpoint              = "https://s3.example.com"
s3_create_bucket         = false
organizations            = ["default", "platform"]
ingest_organization      = "platform"
web_url                  = "https://o2.example.com"
host_network             = "private"
extra_env                = { ZO_COMPACT_DATA_RETENTION_DAYS = "30" }
