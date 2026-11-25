# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Forgejo behind a TLS-terminating proxy (the proxy serves
# https://forgejo.internal/ and forwards to port 3000), RustFS reached at a
# fixed address in another namespace, no SSH.
#   norca rigger install ./modules/forgejo -name forgejo -f modules/forgejo/examples/behind-proxy.vars.hcl
domain      = "forgejo.internal"
root_url    = "https://forgejo.internal/"
ssh_enabled = false

storage_endpoint = "10.0.0.10:9000"
storage_bucket   = "forgejo"

resources = {
  cpu    = 2000
  memory = 2048
}
