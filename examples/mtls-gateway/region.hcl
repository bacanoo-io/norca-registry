# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The gateway of region eu-1 on the nodes that are on the VPN between the
# clouds (node meta vpn = "true"), bound to the VPN interface.
#   norca pack run mtls-gateway --registry=norca -f examples/mtls-gateway/region.hcl
region       = "eu-1"
host_network = "vpn"

constraints = [
  {
    attribute = "$${meta.vpn}"
    operator  = "="
    value     = "true"
  },
]
