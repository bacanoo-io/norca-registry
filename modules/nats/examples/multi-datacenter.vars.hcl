# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One region over three datacenters (availability zones): one NATS server per
# datacenter, kept apart by the fork's separate rule on the datacenter, so the
# servers and the JetStream streams survive the loss of a datacenter.
#   norca secret put nats/users/app password=-
#   norca pack run nats --registry=norca --name=nats -f examples/nats/multi-datacenter.hcl
datacenters       = ["eu-a", "eu-b", "eu-c"]
count             = 3
separate_scope    = "$${node.datacenter}"
separate_required = true

jetstream_enabled = true
# Replicas of every stream in different datacenters (servers are tagged
# dc:<datacenter>), and compressed routes between the datacenters.
jetstream_unique_tag = "dc"
cluster_compression  = "s2_auto"

auth_mode = "userpass"
users = [
  {
    name            = "app"
    publish_allow   = ["app.>", "$JS.API.>"]
    subscribe_allow = ["app.>", "_INBOX.>"]
  },
]
