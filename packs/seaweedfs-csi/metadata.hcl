# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://github.com/bacanoo-io/seaweedfs-csi-driver"
}

pack {
  name        = "seaweedfs-csi"
  description = "The SeaweedFS CSI driver (Apache-2.0, binaries referenced, never shipped) on every node with raw_exec: the mount service (weed mount, FUSE) and the driver as a monolith CSI plugin (controller and node) with volume statistics and conditions, the filer found in the native catalog."
  version     = "0.1.0"

  requires {
    norca = ">= 0.3.0"
  }
}
