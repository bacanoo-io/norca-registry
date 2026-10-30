# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Three NATS servers with user/password authentication: the users in NATS
# accounts, their passwords in the built-in secret store (one secret per user,
# item password).
#   norca secret put nats/users/openobserve password=-
#   norca secret put nats/users/orders password=-
#   norca secret put nats/users/ops password=-
#   norca pack run nats --registry=norca --name=nats -f examples/nats/userpass.hcl
auth_mode = "userpass"

users = [
  # OpenObserve in cluster mode (openobserve pack): its own account with its
  # JetStream KV buckets and streams, invisible to the other accounts.
  { name = "openobserve", account = "OPENOBSERVE" },
  # An application in the shared account APP: its own subjects, JetStream
  # consumers.
  {
    name            = "orders"
    publish_allow   = ["orders.>", "$JS.API.>"]
    subscribe_allow = ["orders.>", "_INBOX.>"]
  },
  # Operators: the system account (nats server report, raft peer-remove).
  { name = "ops", account = "SYS" },
]
