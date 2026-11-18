# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One server with raw_exec from a release archive, JetStream in a path of
# the node, the configuration of the Variable, and settings of its own.
count                      = 1
driver                     = "raw_exec"
artifact_url               = "https://mirror.example.com/nats-server-v2.15.0-linux-amd64.tar.gz"
artifact_checksum          = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
binary                     = "local/nats-server"
storage                    = "path"
store_path                 = "/srv/nats"
auth_mode                  = "config"
secrets_variable           = "nats/config"
distinct_hosts             = false
disruption_max_unavailable = ""
separate_scope             = "rack"
separate_required          = true
datacenters                = []
node_pool                  = "messaging"
extra_config               = <<EOT
max_payload: 4MB

write_deadline: "10s"
EOT
