# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One region over three datacenters (availability zones): one NATS server per
# datacenter, kept apart by the fork's separate rule on the datacenter, and
# the event stream bridge into a JetStream stream with three replicas, so the
# servers and the event history survive the loss of a datacenter.
#   norca secret put nats/users/app password=-
#   nk -gen user > bridge.seed && nk -inkey bridge.seed -pubout   # the public key: bridge_nkey
#   norca secret put nats/users/natsbridge seed=@bridge.seed
#   norca pack run nats --registry=norca --name=nats -f examples/nats/multi-datacenter.hcl
datacenters       = ["eu-a", "eu-b", "eu-c"]
count             = 3
separate_scope    = "$${node.datacenter}"
separate_required = true

jetstream_enabled = true

auth_mode = "userpass"
users = [
  {
    name            = "app"
    publish_allow   = ["app.>", "$JS.API.>"]
    subscribe_allow = ["app.>", "nomad.>", "_INBOX.>"]
  },
]

bridge_enabled = true
# Two bridges on different nodes; one publishes, the other takes over.
bridge_count = 2
# Replace with the public key of your bridge.seed (this one is an example).
bridge_nkey = "UDXU4RCSJNZOIQHZNWXHXORDPRTGNJAHAHFRGZNEEJCPQTT2M7NLCNF4"
# The stream NORCA_EVENTS_<region> on all three servers (norca-natsbridge
# with -jetstream-replicas; an older bridge creates it with one replica).
bridge_jetstream_replicas = 3
