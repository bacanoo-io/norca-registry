# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# norca-acme for issuers of the Let's Encrypt staging directory, with the
# HTTP-01 challenge behind the traefik module and DNS-01 for the zones of
# norca-provider. The issuer is an object of its own:
#
#   kind = "norca.io/CertificateIssuer"
#   name = "letsencrypt-staging"
#   spec {
#     external {
#       controller = "norca-acme"
#       config {
#         directory = "https://acme-staging-v02.api.letsencrypt.org/directory"
#         email     = "ops@example.com"
#         # The staging roots are not in the system roots: download them from
#         # the documentation of the certificate authority.
#         roots     = "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
#       }
#     }
#   }
#
#   norca rigger install ./modules/norca-acme -name norca-acme -namespace norca-system -f modules/norca-acme/examples/letsencrypt-staging.vars.hcl
datacenters        = ["dc1", "dc2"]
http01_entrypoints = ["web"]
retry_base         = "2m"
