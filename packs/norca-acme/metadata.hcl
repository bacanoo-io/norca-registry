# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

app {
  url = "https://github.com/bacanoo-io/norca-platform"
}

pack {
  name        = "norca-acme"
  description = "The ACME operator of Norca (norca-acme of norca-platform) as one release: the ACL policy bound to its job and the job, which is the controller of the norca.io/CertificateIssuer objects that sign through an ACME certificate authority such as Let's Encrypt. It fulfils the certificate orders of the servers, answers the HTTP-01 challenge behind the edge router and proves names in DNS zones through norca-provider."
  version     = "0.1.0"

  requires {
    norca    = ">= 0.3.0"
    features = ["releases", "custom-objects"]
  }
}
