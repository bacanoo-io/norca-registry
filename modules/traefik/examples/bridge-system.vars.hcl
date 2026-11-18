# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A system job in bridge mode on a host network, two certificates and a
# default of its own, a UDP entrypoint, the dashboard, metrics and access
# logs, and no catalog provider.
job_type                = "system"
network_mode            = "bridge"
host_network            = "public"
access_log              = true
dashboard               = true
metrics                 = true
catalog_enabled         = false
tls_certificates        = ["certs/shop", "certs/api"]
tls_default_certificate = "certs/wildcard"
tls_cert_item           = "crt"
entrypoints = [
  { name = "web", port = 80, protocol = "http", redirect_to = "web-secure" },
  { name = "web-secure", port = 443, protocol = "https" },
  { name = "dns", port = 53, protocol = "udp" },
]
dynamic_config = <<EOT
http:
  routers:
    shop:
      rule: "Host(`shop.example.com`)"
      service: shop
EOT
