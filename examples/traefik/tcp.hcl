# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Raw TCP: PostgreSQL on its own entrypoint (5432, any client, HostSNI(`*`)
# as plain TCP has no name), and TLS passthrough on 443: connections whose
# SNI name is mq.example.com go unterminated to a backend that holds its own
# certificate, the others are HTTPS of Traefik. A UDP entrypoint (DNS on 53)
# shows the same for UDP.
#   norca pack run traefik --registry=norca --name=traefik -f examples/traefik/tcp.hcl
entrypoints = [
  { name = "websecure", port = 443, protocol = "https" },
  { name = "postgres", port = 5432, protocol = "tcp" },
  { name = "dns", port = 53, protocol = "udp" },
]

dynamic_config = <<-EOT
  tcp:
    routers:
      postgres:
        rule: HostSNI(`*`)
        entryPoints: [postgres]
        service: postgres
      mq:
        rule: HostSNI(`mq.example.com`)
        entryPoints: [websecure]
        service: mq
        tls:
          passthrough: true
    services:
      postgres:
        loadBalancer:
          servers:
            - address: 10.0.1.40:5432
      mq:
        loadBalancer:
          servers:
            - address: 10.0.1.50:5671
            - address: 10.0.1.51:5671
  udp:
    routers:
      dns:
        entryPoints: [dns]
        service: dns
    services:
      dns:
        loadBalancer:
          servers:
            - address: 10.0.1.53:53
EOT
