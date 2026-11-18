# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "mtls-gateway"
  version     = "0.2.1"
  description = "The cross-region native mTLS gateway of a Norca region (mtls { mode = \"gateway\" }): an SNI passthrough Envoy on every node of the region, injected by the servers or defined by the pack."
  url         = "https://github.com/bacanoo-io/norca/blob/main/docs/native-mtls.md"

  requires {
    norca = ">= 0.1.0"
  }
}
