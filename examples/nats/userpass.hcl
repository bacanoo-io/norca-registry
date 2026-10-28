# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three NATS servers with user/password authentication: the users in NATS
# accounts, their passwords in the built-in secret store (one secret per user,
# item password), the event stream bridge as an NKey user.
#   norca secret put nats/users/openobserve password=-
#   norca secret put nats/users/orders password=-
#   norca secret put nats/users/ops password=-
#   nk -gen user > bridge.seed && nk -inkey bridge.seed -pubout   # the public key: bridge_nkey
#   norca secret put nats/users/natsbridge seed=@bridge.seed
#   norca pack run nats --registry=norca --name=nats -f examples/nats/userpass.hcl
auth_mode = "userpass"

users = [
  # OpenObserve in cluster mode (openobserve pack): its own account with its
  # JetStream KV buckets and streams, invisible to the other accounts.
  { name = "openobserve", account = "OPENOBSERVE" },
  # An application in the shared account APP: its own subjects, the Norca
  # events of the bridge, JetStream consumers.
  {
    name            = "orders"
    publish_allow   = ["orders.>", "$JS.API.>"]
    subscribe_allow = ["orders.>", "nomad.>", "_INBOX.>"]
  },
  # Operators: the system account (nats server report, raft peer-remove).
  { name = "ops", account = "SYS" },
]

bridge_enabled = true
# Replace with the public key of your bridge.seed (this one is an example).
bridge_nkey ="UDXU4RCSJNZOIQHZNWXHXORDPRTGNJAHAHFRGZNEEJCPQTT2M7NLCNF4"

# The bridge also syncs the cluster pack registries on push notices
# (norca-natsbridge notify-push) and on the registry events of other regions;
# its ACL policy then needs the registry permissions (see the pack output).
bridge_sync_pushes  = true
bridge_sync_regions = true
