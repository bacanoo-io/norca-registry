# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Hetzner Cloud load balancers on https, with the secrets in the job's
# Variable (items PROVIDER_TOKEN, HCLOUD_TOKEN, tls_cert, tls_key), in the
# namespace of the job (the namespace of the release, norca-system):
#   norca var put -namespace norca-system nomad/jobs/norca-provider PROVIDER_TOKEN=... HCLOUD_TOKEN=... tls_cert=@tls.crt tls_key=@tls.key
#   norca var put -namespace norca-system providers/hetzner-eu token=...   # the same token, for the LoadBalancer operator
#   rigger install ./modules/norca-provider -name norca-provider -namespace norca-system -f modules/norca-provider/examples/hetzner.vars.hcl
secrets       = true
tls_enabled   = true
advertise_url = "https://norca-provider.service.norca-system.norca:8443"
providers     = <<EOT
[
  {
    "name": "hetzner-eu",
    "type": "hcloud",
    "params": { "token": "env:HCLOUD_TOKEN" },
    "token": "env:PROVIDER_TOKEN",
    "token_variable": "providers/hetzner-eu",
    "loadbalancer": {
      "classes": [
        { "class": "hcloud-fsn1", "params": { "location": "fsn1" } }
      ]
    }
  }
]
EOT
