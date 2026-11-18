# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# A filer at a fixed address, the driver binaries from an archive, weed
# installed on the nodes, and only the nodes with storage.
filer                      = "10.0.0.5:8888"
binaries_artifact_url      = "https://mirror.example.com/seaweedfs-csi/linux_amd64.tar.gz"
binaries_artifact_checksum = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
driver_binary              = "local/seaweedfs-csi-driver"
mount_binary               = "local/seaweedfs-mount"
weed_artifact_url          = ""
weed_binary                = "/usr/local/bin/weed"
cache_capacity_mb          = 512
driver_args                = ["-concurrentWriters=32"]
constraints                = [{ attribute = "$${meta.storage}", operator = "=", value = "true" }]
node_pool                  = "storage"
