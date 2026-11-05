[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
Node scaling operator "[[ $v.job_name ]]" in namespace [[ $v.namespace ]]: [[ $v.count ]] instance(s) in the node pool [[ $v.node_pool ]], driver [[ $v.driver ]].

It reads the bootstrap and the network ranges of the region from the
Variables nodescaler/bootstrap/<region> and nodescaler/network/<region> in the
namespace [[ $v.variables_namespace ]], which norca-deployer writes with
node_scaling (and a node CA from `norca-deployer pki issue-node-ca`).

Register a provider (it writes its own norca.io/NodeProvider object), then a
node group:
  norca object apply workers-dc-a.hcl     # kind = "norca.io/NodeGroup", provider = "<provider>"
  norca object get norca.io/NodeGroup workers-dc-a
  norca object events norca.io/NodeGroup workers-dc-a
