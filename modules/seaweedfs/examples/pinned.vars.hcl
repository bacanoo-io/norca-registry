# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The server on the node storage-1, on the weed binary installed there, with
# a constraint of its own and an extra argument.
node        = "storage-1"
datacenters = ["dc1", "dc2"]
node_pool   = "storage"
constraints = [
  { attribute = "$${meta.storage}", operator = "=", value = "true" },
  { attribute = "$${attr.kernel.name}", operator = "is_set", value = "" },
]
artifact_url = ""
binary       = "/usr/local/bin/weed"
extra_args   = ["-volume.index=leveldb"]
replication  = "001"
volume_max   = 20
