# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Four RustFS servers, one per storage node, the drives erasure coded across
# them. The nodes carry the host volume "rustfs" and the meta storage = "s3".
#   norca secret put -namespace storage rustfs/root access_key=norca-backup secret_key=-
#   norca pack run rustfs --registry=norca -f examples/rustfs/distributed.hcl
namespace = "storage"
mode      = "distributed"
nodes     = ["10.0.1.11", "10.0.1.12", "10.0.1.13", "10.0.1.14"]
buckets   = ["norca-backup"]

constraints = [
  {
    attribute = "$${meta.storage}"
    operator  = "="
    value     = "s3"
  },
]

resources = {
  cpu    = 1000
  memory = 2048
}
