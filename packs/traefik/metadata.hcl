# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://traefik.io/traefik/"
}

pack {
  name        = "traefik"
  description = "Traefik Proxy (MIT) as the edge router of a region: entrypoints for HTTP, HTTPS, TCP and UDP set from the install form, certificates from the secret store, routes from the tags of the services in Norca's native catalog and from static file configuration (web, WebSocket, gRPC, TCP)."
  version     = "0.1.0"

  requires {
    norca = ">= 0.3.0"
  }
}

ui {
  tab "general" {
    label = "General"
    icon  = "settings"
  }
  tab "entrypoints" {
    label = "Entrypoints"
    icon  = "network"
  }
  tab "tls" {
    label = "TLS"
    icon  = "key"
  }
  tab "routing" {
    label = "Routing"
    icon  = "route"
  }
  tab "resources" {
    label = "Resources"
    icon  = "cpu"
  }
}
