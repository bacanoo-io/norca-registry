# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The edge for certificates from an ACME certificate authority: port 80
# redirects to 8443 except for the path of the HTTP-01 challenge, which the
# norca-acme pack routes to its service by catalog tags. The certificate is
# the secret a norca.io/Certificate object keeps (secret_path = "certs/web").
# norca-acme runs in the namespace norca-system: Traefik reads the services
# there with a policy bound to its job (the output of the pack prints it,
# with namespace "norca-system" in place of "*" for this one only).
#   norca pack run traefik --registry=norca --name=traefik -f examples/traefik/acme.hcl
#   norca acl policy apply -namespace default -job traefik traefik-catalog policy.hcl
#   norca pack run norca-acme --registry=norca --name=acme
entrypoints = [
  { name = "web", port = 80, protocol = "http", redirect_to = "websecure" },
  { name = "websecure", port = 8443, protocol = "https" },
]

acme_challenge     = true
catalog_namespaces = ["default", "norca-system"]

tls_certificates = ["certs/web"]
