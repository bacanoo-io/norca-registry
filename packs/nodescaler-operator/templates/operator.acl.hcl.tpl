[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
policy [[ printf "%s" $v.job_name | quote ]] {
  description = "Permissions of the node scaling operator (bound to its job)"
  rules       = <<EOT
# A namespace of its own replaces the rules of "*" for it, so every block
# repeats the capabilities on the jobs (see the namespace "*").
namespace "[[ $v.namespace ]]" {
  capabilities = ["list-jobs", "read-job"]

  variables {
    # The leader election lease of the operator instances.
    path "controller-lease/nodescaler*" {
      capabilities = ["list", "read", "write"]
    }
  }
}

namespace "[[ $v.variables_namespace ]]" {
  capabilities = ["list-jobs", "read-job"]

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
# group, never its spec (the scale is the autoscaler's or a person's). A scale
# down reads the jobs of the allocations on a node: whether one could be
# placed again elsewhere (distinct_hosts).
namespace "*" {
  capabilities = ["list-jobs", "read-job"]

  object "norca.io/NodeGroup" {
    capabilities = ["read", "write-status", "write-events"]
  }

  object "norca.io/NodeProvider" {
    capabilities = ["read"]
  }
}

# The nodes: matched with the instances, a foreign node made ineligible, and
# for a scale down drained, made eligible again and purged once down.
node {
  policy = "write"
}
EOT

  job_acl {
    namespace = [[ $v.namespace | quote ]]
    job_id    = [[ $v.job_name | quote ]]
  }
}
