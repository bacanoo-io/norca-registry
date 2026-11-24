# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

policy "operator" {
  name        = var.job_name
  description = "Permissions of the node scaling operator (bound to its job)"
  rules {
    # A namespace of its own replaces the rules of "*" for it, so every block
    # repeats the capabilities on the jobs (see the namespace "*"). The
    # namespace of the job holds the Variables under nodescaler/ too, unless
    # variables_namespace names another one: then they have a block of their
    # own below.
    dynamic "namespace" {
      for_each = [rigger.namespace]
      labels   = [namespace.value]

      content {
        capabilities = ["list-jobs", "read-job"]

        object "norca.io/LoadBalancer" {
          capabilities = ["read"]
        }

        variables {
          # The leader election lease of the operator instances.
          path "controller-lease/nodescaler*" {
            capabilities = ["list", "read", "write"]
          }

          # The bootstrap of the region (with the key of the node CA), the
          # network ranges, and the tokens of the providers.
          dynamic "path" {
            for_each = local.vars_here ? ["nodescaler/*"] : []
            labels   = [path.value]

            content {
              capabilities = ["list", "read"]
            }
          }

          # The records of the nodes that join with a key of their own: the
          # one-time tokens and the serials of the latest certificates.
          dynamic "path" {
            for_each = local.vars_here ? ["nodescaler/join/*"] : []
            labels   = [path.value]

            content {
              capabilities = ["list", "read", "write", "destroy"]
            }
          }
        }
      }
    }

    dynamic "namespace" {
      for_each = local.vars_here ? [] : [local.vars]
      labels   = [namespace.value]

      content {
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
  }

  job_acl {
    namespace = rigger.namespace
    job_id    = var.job_name
  }
}
