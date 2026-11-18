# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# TLS everywhere, a gateway to two other regions, leaf nodes, NKey users,
# servers on a host network with fixed ports, JetStream tuned.
tls_enabled                       = true
tls_verify_clients                = true
auth_mode                         = "nkey"
gateway_enabled                   = true
remote_gateways                   = [{ name = "us", urls = ["nats://us-1:7222", "nats://us-2:7222"] }, { name = "ap", urls = [] }]
leafnodes_enabled                 = true
host_network                      = "vpn"
cluster_name                      = "eu-central"
cluster_compression               = "s2_auto"
cluster_pool_size                 = 3
jetstream_domain                  = "eu"
jetstream_unique_tag              = "dc"
jetstream_server_tags             = ["ssd", "zone:a"]
jetstream_sync_interval           = "2m"
jetstream_max_outstanding_catchup = "64MB"
metrics_enabled                   = true
metrics_port                      = 7777
debug                             = true
