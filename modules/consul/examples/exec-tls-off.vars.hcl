# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Servers and clients with the exec driver from the release archive, TLS
# off, five servers one per datacenter, extra configuration, a host network.
driver                       = "exec"
download_checksum            = "sha256:4444444444444444444444444444444444444444444444444444444444444444"
tls_enabled                  = false
server_count                 = 5
datacenter_separate_required = true
host_network                 = "private"
datacenter                   = "eu1"
domain                       = "internal"
ui_enabled                   = false

# Consul configuration of your own, as objects: written as consul.d/extra.json.
server_extra_config = {
  limits = {
    http_max_conns_per_client = 400
  }

  autopilot = {
    cleanup_dead_servers = true
  }
}

client_extra_config = {
  log_json = true
}

# The installer's acceptance of the Consul license (BSL 1.1): read it first.
consul_license_accepted = true
