# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# TLS from a secret, required; two databases, no monitoring role; dumps to
# an S3 endpoint over TLS; a pinned image on a host network.
tls_mode           = "secret"
tls_required       = true
monitoring_enabled = false
host_network       = "private"
image_digest       = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
databases = [
  { name = "shop", user = "shop", secret_path = "postgres/shop" },
  { name = "reports", user = "reporting", secret_path = "postgres/reports" },
]
dump_enabled          = true
dump_storage_endpoint = "s3.example.com:443"
dump_storage_use_ssl  = true
