# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The edge for certificates from an ACME certificate authority: port 80
# redirects to 8443 except for the path of the HTTP-01 challenge, which the
# norca-acme module routes to its service by catalog tags. The certificate is
# the secret a norca.io/Certificate object keeps (secret_path = "certs/web").
# norca-acme runs in the namespace norca-system: Traefik reads the services
# there with a policy bound to its job (the notes of the module print it,
# with namespace "norca-system" in place of "*" for this one only).
#   rigger install ./modules/traefik -name traefik -f modules/traefik/examples/acme.vars.hcl
#   norca acl policy apply -namespace default -job traefik traefik-catalog policy.hcl
#   rigger install ./modules/norca-acme -name acme -namespace norca-system
entrypoints = [
  { name = "web", port = 80, protocol = "http", redirect_to = "websecure" },
  { name = "websecure", port = 8443, protocol = "https" },
]

acme_challenge     = true
catalog_namespaces = ["default", "norca-system"]

tls_certificates = ["certs/web"]
