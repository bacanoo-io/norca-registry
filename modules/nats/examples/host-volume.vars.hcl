# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# JetStream on a host volume with the exec driver, users in two accounts
# with permissions, the system account among them, and the changes of the
# region in an account of their own.
driver            = "exec"
storage           = "host_volume"
auth_mode         = "userpass"
system_account    = "SYS"
norca_bus_leaf    = true
norca_bus_servers = ["10.0.0.1:4652"]
norca_bus_tls     = false
norca_bus_account = "CDC"
users = [
  { name = "app", publish_allow = ["orders.>"], subscribe_allow = ["orders.>", "_INBOX.>"], allow_responses = true },
  { name = "admin", account = "SYS" },
  { name = "audit", account = "CDC", subscribe_deny = ["secret.>"] },
]
