# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Traefik in front of a backend that accepts native mTLS only. Traefik gets a
# workload certificate (mtls) and presents it to the backend api through the
# servers transport mtls-api; the client renews the certificate and Traefik
# applies it without a restart.
#   norca pack run traefik --registry=norca --name=traefik -f examples/traefik/mtls.hcl
# The backend: a service in app mode that serves TLS with its own workload
# certificate and requires a client certificate, routed by its tags:
#   service {
#     name     = "api"
#     port     = "https"
#     provider = "nomad"
#     tags = [
#       "traefik.enable=true",
#       "traefik.http.routers.api.rule=Host(`api.example.com`)",
#       "traefik.http.services.api.loadbalancer.server.scheme=https",
#       "traefik.http.services.api.loadbalancer.serversTransport=mtls-api@file",
#     ]
#     mtls {
#       mode = "app"
#     }
#   }
# The intention that lets Traefik (the service named after the job) reach it:
#   norca service intention create -allow traefik api
entrypoints = [
  { name = "web", port = 80, protocol = "http" },
]

mtls = true

mtls_backends = [
  { name = "api", service = "api" },
]
