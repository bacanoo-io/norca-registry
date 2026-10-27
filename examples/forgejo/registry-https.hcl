# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Forgejo as the git server and container registry of the cluster, serving
# HTTPS itself on port 443 with the certificate in the secret forgejo/tls,
# its objects in the RustFS of the rustfs pack (service "rustfs" in the same
# namespace), a nightly dump into the bucket forgejo-dump, and /metrics with
# the token of the secret forgejo/metrics for the otel-collector pack.
#   norca pack run forgejo --registry=norca --name=forgejo -f examples/forgejo/registry-https.hcl
domain        = "forgejo.internal"
http_port     = 443
https_enabled = true

admin_email = "ops@example.internal"

dump_enabled = true
dump_cron    = "30 2 * * *"

extra_env = {
  FORGEJO__mailer__ENABLED = "false"
}

metrics_enabled = true
