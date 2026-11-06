# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The nodes make their own keys: the join endpoint on port 8490 of the
# operator's nodes, behind a stable name, certificates of 7 days renewed at
# two thirds. The machines of the node groups need norca-join
# (/usr/local/bin/norca-join, the item join_binary of the bootstrap).
#   norca pack run nodescaler-operator --registry=norca -f examples/nodescaler-operator/join.hcl
#   norca object events norca.io/NodeGroup workers-dc-a   # CertificateIssued, CertificateRenewed
node_pool     = "system"
join_enabled  = true
join_port     = 8490
join_validity = "168h"
join_urls     = ["https://nodescaler-join.example.com:8490"]
