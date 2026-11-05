[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
policy [[ printf "%s" $v.job_name | quote ]] {
  description = "Permissions of the node scaling operator (bound to its job)"
  rules       = <<EOT
namespace "[[ $v.namespace ]]" {
  variables {
    # The leader election lease of the operator instances.
    path "controller-lease/nodescaler*" {
      capabilities = ["list", "read", "write"]
    }
  }
}

namespace "[[ $v.variables_namespace ]]" {
  variables {
    # The bootstrap of the region (with the key of the node CA), the
    # network ranges, and the tokens of the providers.
    path "nodescaler/*" {
      capabilities = ["list", "read"]
    }
  }
}

# The node groups and the providers are cluster-scoped: their rules are in
# the namespace "*". The operator writes the status and the event log of a
# group, never its spec (the scale is the autoscaler's or a person's).
namespace "*" {
  object "norca.io/NodeGroup" {
    capabilities = ["read", "write-status", "write-events"]
  }

  object "norca.io/NodeProvider" {
    capabilities = ["read"]
  }
}

# The nodes: matched with the instances, and a foreign node made ineligible.
node {
  policy = "write"
}
EOT

  job_acl {
    namespace = [[ $v.namespace | quote ]]
    job_id    = [[ $v.job_name | quote ]]
  }
}
