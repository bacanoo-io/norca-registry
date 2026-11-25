# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A lab with a test certificate authority (Pebble) and a name server that
# takes dynamic updates: the directory has a certificate of a test CA, the
# DNS provider is called over http, and the name servers of the zone are
# found through the name server itself.
#
#   norca rigger install ./modules/norca-acme -name norca-acme -namespace norca-system -f modules/norca-acme/examples/lab.vars.hcl
log_level               = "debug"
interval                = "2s"
retry_base              = "10s"
retry_max               = "1m"
max_attempts            = 5
zone_allow_http         = true
dns_resolver            = "10.0.0.53:53"
dns_propagation_timeout = "1m"
acme_ca_cert            = <<EOT
-----BEGIN CERTIFICATE-----
MIIBtestcertificateofthelabca
-----END CERTIFICATE-----
EOT
