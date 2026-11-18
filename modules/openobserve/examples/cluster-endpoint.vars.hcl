# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Cluster mode over plain HTTP, PostgreSQL at a fixed endpoint, S3 of the
# catalog over TLS.
mode              = "cluster"
tls_mode          = "none"
postgres_endpoint = "pg.example.com:5432"
s3_use_ssl        = true
