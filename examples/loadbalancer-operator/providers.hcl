# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Load balancers from providers (norca-provider) whose tokens are in the
# namespace ops and whose https certificates come from the CA of the cluster.
#   norca pack run loadbalancer-operator --registry=norca -f examples/loadbalancer-operator/providers.hcl
class_token_namespace = "ops"
class_token_path      = "providers/*"
class_ttl             = "2m"
class_ca_cert         = <<EOT
-----BEGIN CERTIFICATE-----
MIIBdzCCAR2gAwIBAgIBATAKBggqhkjOPQQDAjAWMRQwEgYDVQQDEwtleGFtcGxl
LWNhMB4XDTI2MDEwMTAwMDAwMFoXDTM2MDEwMTAwMDAwMFowFjEUMBIGA1UEAxML
ZXhhbXBsZS1jYTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABExampleOnly0000
-----END CERTIFICATE-----
EOT
