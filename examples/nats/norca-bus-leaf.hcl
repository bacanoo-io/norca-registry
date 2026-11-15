# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# One NATS server that receives the changes of the Norca region as a leaf
# node of the system bus (change data capture). The Norca servers run the
# leaf node listener (server { bus { leafnodes { enabled = true } } }); the
# secret norca/bus/leaf holds the token of a policy with
# cdc { receive = [...] leaf = true } and the CA of the Norca servers:
#   norca secret put norca/bus/leaf token=<secret ID> ca=@/etc/norca.d/ca.pem
#   norca pack run nats --registry=norca --name=nats-cdc -f examples/nats/norca-bus-leaf.hcl
job_name          = "nats-cdc"
count             = 1
client_port       = 4322
monitor_port      = 8322
norca_bus_leaf    = true
norca_bus_servers = ["10.0.0.11:4652", "10.0.0.12:4652", "10.0.0.13:4652"]
