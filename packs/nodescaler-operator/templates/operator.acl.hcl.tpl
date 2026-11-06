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

  object "norca.io/LoadBalancer" {
    capabilities = ["read"]
  }

  variables {
    # The leader election lease of the operator instances.
    path "controller-lease/nodescaler*" {
      capabilities = ["list", "read", "write"]
    }
  }
}

namespace "[[ $v.variables_namespace ]]" {
  capabilities = ["list-jobs", "read-job"]

  object "norca.io/LoadBalancer" {
    capabilities = ["read"]
  }

  variables {
    # The bootstrap of the region (with the key of the node CA), the
    # network ranges, and the tokens of the providers.
    path "nodescaler/*" {
      capabilities = ["list", "read"]
    }

    # The records of the nodes that join with a key of their own: the
    # one-time tokens and the serials of the latest certificates.
    path "nodescaler/join/*" {
      capabilities = ["list", "read", "write", "destroy"]
    }
  }
}

# The node groups and the providers are cluster-scoped: their rules are in
# the namespace "*". The operator writes the status and the event log of a
# group, never its spec (the scale is the autoscaler's or a person's), and
# its finalizer, which keeps a deleted group until its instances are dealt
# with. It reports orphaned instances in the event log of their provider. A
# scale down reads the jobs of the allocations on a node: whether one could
# be placed again elsewhere (distinct_hosts). It reads the load balancers of
# every namespace: a node behind one leaves it before its drain (the
# namespaces above repeat this rule, as a namespace of its own replaces "*").
namespace "*" {
  capabilities = ["list-jobs", "read-job"]

  object "norca.io/NodeGroup" {
    capabilities = ["read", "write-status", "write-events", "manage-finalizers"]
  }

  object "norca.io/NodeProvider" {
    capabilities = ["read", "write-events"]
  }

  object "norca.io/LoadBalancer" {
    capabilities = ["read"]
  }
}

# The nodes: matched with the instances, a foreign node made ineligible, and
# for a scale down drained, made eligible again and purged once down; the
# meta norca.lb.leaving of an edge node before its drain.
node {
  policy = "write"
}
EOT

  job_acl {
    namespace = [[ $v.namespace | quote ]]
    job_id    = [[ $v.job_name | quote ]]
  }
}
