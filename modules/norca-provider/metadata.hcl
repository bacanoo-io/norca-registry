# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

module {
  name        = "norca-provider"
  version     = "0.5.0"
  description = "The provider application of Norca (norca-provider of norca-platform) as one release: the ACL policy bound to its job and the job, which serves the node providers of the node scaling operator, the load balancer classes of the LoadBalancer operator and the DNS zones of norca-acme its configuration names, and registers them as NodeProvider, LoadBalancerClass and DNSZone objects; and the norca.io/DNSZone object kind."
  url         = "https://github.com/bacanoo-io/norca-platform"

  requires {
    norca    = ">= 0.3.0"
    features = ["releases", "custom-objects"]
  }
}
