# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

host_network = "vpn"

constraints = [
  {
    attribute = "$${meta.vpn}"
    operator  = "="
    value     = "true"
  },
]
