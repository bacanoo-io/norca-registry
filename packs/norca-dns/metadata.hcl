# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://github.com/bacanoo-io/norca-platform"
}

pack {
  name        = "norca-dns"
  description = "The DNS records operator of Norca (norca-dns of norca-platform) as one release: the norca.io/DNSRecord object kind, the ACL policy bound to its job and the job, which keeps the record sets of the DNSRecord objects (A, AAAA, CNAME, TXT; values given or taken from a LoadBalancer object) in the DNS zones of norca-provider that allow records, under the allow list of each namespace."
  version     = "0.1.1"

  requires {
    norca    = ">= 0.3.0"
    features = ["releases", "custom-objects"]
  }
}
