# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# DNS-01 only, in a container, the tokens of the zones in another
# namespace, DNS providers behind a private CA.
driver               = "docker"
image                = "registry.example.com/norca/norca-acme:0.1.0"
http01_enabled       = false
zone_token_namespace = "dns"
zone_ca_cert         = "-----BEGIN CERTIFICATE-----\nMIIBzone\n-----END CERTIFICATE-----"
