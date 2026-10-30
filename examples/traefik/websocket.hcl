# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# WebSocket connections (wss://ws.example.com/socket): Traefik passes the
# Upgrade of HTTP/1.1 through by itself, nothing to switch on. A sticky
# cookie keeps a client on the backend that holds its session state, and the
# health check takes a failed backend out of the rotation; open connections
# stay on their backend until they close.
#   norca secret put traefik/certs/ws-example-com cert=@fullchain.pem key=@privkey.pem
#   norca pack run traefik --registry=norca --name=traefik -f examples/traefik/websocket.hcl
entrypoints = [
  { name = "web", port = 80, protocol = "http", redirect_to = "websecure" },
  { name = "websecure", port = 443, protocol = "https" },
]

tls_certificates = ["traefik/certs/ws-example-com"]

dynamic_config = <<-EOT
  http:
    routers:
      realtime:
        rule: Host(`ws.example.com`) && PathPrefix(`/socket`)
        entryPoints: [websecure]
        service: realtime
    services:
      realtime:
        loadBalancer:
          sticky:
            cookie:
              name: realtime_affinity
              secure: true
              httpOnly: true
              sameSite: lax
          servers:
            - url: http://10.0.1.20:3000
            - url: http://10.0.1.21:3000
          healthCheck:
            path: /health
            interval: 10s
EOT
