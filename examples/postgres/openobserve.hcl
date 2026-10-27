# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# PostgreSQL as the metadata store of OpenObserve in cluster mode, in the
# namespace of the observability stack: the database and role openobserve,
# the monitoring role of the otel-collector pack.
#   norca secret put -namespace observability postgres/superuser password=-
#   norca secret put -namespace observability postgres/openobserve password=-
#   norca secret put -namespace observability postgres/monitoring password=-
#   norca pack run postgres --registry=norca -f examples/postgres/openobserve.hcl
namespace = "observability"

databases = [
  {
    name        = "openobserve"
    user        = "openobserve"
    secret_path = "postgres/openobserve"
  },
]

settings = {
  max_connections = "200"
  shared_buffers  = "256MB"
}
