# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "nats"
  version     = "2.0.0"
  description = "A NATS cluster per Norca region (JetStream, supercluster gateways, TLS and client auth from Variables, or users in accounts with passwords from the built-in secret store)."
  url         = "https://nats.io"

  requires {
    norca = ">= 0.1.0"
  }
}
