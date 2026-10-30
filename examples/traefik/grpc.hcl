# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# gRPC: clients connect over TLS (HTTP/2 negotiated with ALPN on the https
# entrypoint), Traefik terminates TLS and talks plaintext HTTP/2 (h2c) to
# the backends, checked with the standard gRPC health protocol
# (grpc.health.v1). For a backend with TLS use https:// in the url.
#   norca secret put traefik/certs/grpc-example-com cert=@fullchain.pem key=@privkey.pem
#   norca pack run traefik --registry=norca --name=traefik -f examples/traefik/grpc.hcl
#   grpcurl grpc.example.com:443 list
entrypoints = [
  { name = "websecure", port = 443, protocol = "https" },
]

tls_certificates = ["traefik/certs/grpc-example-com"]
tls_min_version  = "VersionTLS13"

dynamic_config = <<-EOT
  http:
    routers:
      orders:
        rule: Host(`grpc.example.com`) && PathPrefix(`/orders.v1.OrderService/`)
        entryPoints: [websecure]
        service: orders
    services:
      orders:
        loadBalancer:
          servers:
            - url: h2c://10.0.1.30:50051
            - url: h2c://10.0.1.31:50051
          healthCheck:
            mode: grpc
            interval: 10s
            timeout: 3s
EOT
