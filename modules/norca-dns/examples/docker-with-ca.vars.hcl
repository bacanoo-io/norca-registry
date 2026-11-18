# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The operator in a container, DNS providers behind a private CA, and the
# policy and the kind left to another release.
driver              = "docker"
image               = "registry.example.com/norca/norca-dns:0.1.1"
zone_ca_cert        = "-----BEGIN CERTIFICATE-----\nMIIBszCCAVmgAwIBAgIUQ0E=\n-----END CERTIFICATE-----\n"
record_kind_enabled = false
acl_policy_enabled  = false
