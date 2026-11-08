# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://github.com/bacanoo-io/norca-platform"
}

pack {
  name        = "norca-provider"
  description = "The provider application of Norca (norca-provider of norca-platform) as one release: the ACL policy bound to its job and the job, which serves the node providers of the node scaling operator and the load balancer classes of the LoadBalancer operator its configuration names, and registers them as NodeProvider and LoadBalancerClass objects."
  version     = "0.1.0"

  requires {
    norca    = ">= 0.3.0"
    features = ["releases", "custom-objects"]
  }
}
