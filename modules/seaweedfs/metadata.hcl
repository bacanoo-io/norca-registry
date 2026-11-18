# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "seaweedfs"
  version     = "0.1.0"
  description = "A single SeaweedFS server (Apache-2.0, release archive referenced, never shipped): master, volume server and filer in one weed process with raw_exec, data in a directory of the node, the master, volume and filer in the native catalog. The storage of the seaweedfs-csi pack."
  url         = "https://github.com/seaweedfs/seaweedfs"

  requires {
    norca = ">= 0.1.0"
  }
}
