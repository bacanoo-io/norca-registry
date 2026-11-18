# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# raw_exec with the binary on the nodes and the data in a path, no clients,
# hourly snapshots to an S3 endpoint with encryption, metrics, an image
# pinned for the other drivers.
driver                  = "raw_exec"
consul_binary           = "/usr/local/bin/consul"
server_data_path        = "/var/lib/consul"
bootstrap_driver        = "raw_exec"
clients_enabled         = false
metrics_enabled         = true
snapshot_enabled        = true
snapshot_s3_bucket      = "norca-backup"
snapshot_s3_prefix      = "consul/"
snapshot_s3_endpoint    = "https://s3.example.com"
snapshot_s3_sse         = "AES256"
snapshot_s3_path_style  = false
snapshot_s3_credentials = false
datacenters             = []
node_pool               = "consul"

# The installer's acceptance of the Consul license (BSL 1.1): read it first.
consul_license_accepted = true
