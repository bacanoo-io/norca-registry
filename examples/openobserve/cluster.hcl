# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# OpenObserve in cluster mode in the namespace observability: PostgreSQL of
# the postgres pack (service "postgres", database and role openobserve),
# NATS of the nats pack (service "nats", JetStream, auth_mode = "userpass"
# with the user openobserve in its own account, e.g.
# examples/nats/userpass.hcl, deployed in the namespace observability), the
# data in the RustFS of the rustfs pack (service "rustfs", the bucket created
# by the bootstrap task).
#   norca secret put -namespace observability openobserve/root password=-
#   norca secret put -namespace observability openobserve/s3 access_key=openobserve secret_key=-
#   norca secret put -namespace observability nats/users/openobserve password=-       # read by the NATS servers
#   norca secret put -namespace observability openobserve/nats username=openobserve password=-   # the same password
#   norca pack run openobserve --registry=norca -f examples/openobserve/cluster.hcl
namespace = "observability"
mode      = "cluster"

roles = {
  router       = { count = 2, cpu = 500, memory = 1024 }
  ingester     = { count = 3, cpu = 2000, memory = 4096 }
  querier      = { count = 2, cpu = 2000, memory = 4096 }
  compactor    = { count = 1, cpu = 1000, memory = 2048 }
  alertmanager = { count = 1, cpu = 250, memory = 512 }
}
