# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "seaweedfs-csi"
  version     = "0.1.1"
  description = "The SeaweedFS CSI driver (Apache-2.0, binaries referenced, never shipped) on every node with raw_exec: the mount service (weed mount, FUSE) and the driver as a monolith CSI plugin (controller and node) with volume statistics and conditions, the filer found in the native catalog."
  url         = "https://github.com/bacanoo-io/seaweedfs-csi-driver"

  requires {
    norca = ">= 0.3.0"
  }
}
