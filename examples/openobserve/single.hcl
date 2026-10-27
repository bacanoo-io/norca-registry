# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A single OpenObserve instance in the namespace observability: SQLite and the
# data on the host volume "openobserve", TLS with Norca's workload
# certificates, the ingest credentials of the collectors written by the
# bootstrap task.
#   norca namespace apply observability
#   norca secret put -namespace observability openobserve/root password=-
#   norca pack run openobserve --registry=norca -f examples/openobserve/single.hcl
namespace = "observability"

resources = {
  cpu    = 2000
  memory = 4096
}

extra_env = {
  ZO_COMPACT_DATA_RETENTION_DAYS = "30"
}
