# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://github.com/bacanoo-io/norca-platform"
}

pack {
  name        = "nodescaler-operator"
  description = "The node scaling operator of Norca (norca-nodescaler of norca-platform) as one release: the ACL policy bound to its job and the job, two instances on different nodes, never on a node the operator created. The kinds NodeGroup and NodeProvider are registered by the core."
  version     = "0.2.0"

  requires {
    norca    = ">= 0.3.0"
    features = ["releases", "custom-objects"]
  }
}
