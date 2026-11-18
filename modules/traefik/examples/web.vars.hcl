# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A website over HTTPS: port 80 redirects to 443, the certificate comes from
# the secret store, a static route sends www.example.com to two fixed
# backends with an active health check and security headers.
#   norca secret put traefik/certs/example-com cert=@fullchain.pem key=@privkey.pem
#   norca pack run traefik --registry=norca --name=traefik -f examples/traefik/web.hcl
# Services of the catalog are routed by their tags as well, e.g.
#   tags = ["traefik.enable=true", "traefik.http.routers.app.rule=Host(`app.example.com`)"]
entrypoints = [
  { name = "web", port = 80, protocol = "http", redirect_to = "websecure" },
  { name = "websecure", port = 443, protocol = "https" },
]

tls_certificates = ["traefik/certs/example-com"]
tls_min_version  = "VersionTLS12"

dynamic_config = <<-EOT
  http:
    routers:
      site:
        rule: Host(`www.example.com`) || Host(`example.com`)
        entryPoints: [websecure]
        service: site
        middlewares: [security-headers, compress]
    middlewares:
      security-headers:
        headers:
          stsSeconds: 31536000
          stsIncludeSubdomains: true
          contentTypeNosniff: true
          frameDeny: true
          referrerPolicy: strict-origin-when-cross-origin
      compress:
        compress: {}
    services:
      site:
        loadBalancer:
          servers:
            - url: http://10.0.1.10:8080
            - url: http://10.0.1.11:8080
          healthCheck:
            path: /healthz
            interval: 10s
            timeout: 3s
EOT
