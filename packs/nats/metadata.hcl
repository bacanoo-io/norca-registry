# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://nats.io"
}

pack {
  name        = "nats"
  description = "A NATS cluster per Norca region (JetStream, supercluster gateways, TLS and client auth from Variables, or users in accounts with passwords from the built-in secret store) and the optional event stream to NATS bridge."
  version     = "0.5.0"

  requires {
    norca = ">= 0.1.0"
  }
}
