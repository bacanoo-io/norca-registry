# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The permissions of the LoadBalancer operator, bound to its controller job.
policy "controller" {
  enabled = var.acl_policy_enabled

  name        = var.job_name
  description = "Permissions of the LoadBalancer operator (bound to its controller job)"
  rules {
    # The namespace of the LoadBalancer objects the controller reconciles:
    # one, or every namespace ("*"). A block of a namespace by name takes the
    # place of "*" for that namespace, so the blocks below repeat these
    # rules when the controller watches every namespace.
    dynamic "namespace" {
      for_each = [local.watch]
      labels   = [namespace.value]

      content {
        # Read services, allocations and jobs; register and purge the proxy
        # jobs (lb-*) the operator owns.
        capabilities = local.acl_capabilities

        variables {
          # The target lists of the proxy jobs (the jobs' own Variables).
          path "nomad/jobs/lb-*" {
            capabilities = ["list", "read", "write", "destroy"]
          }

          # Leader election leases of the controller instances.
          dynamic "path" {
            for_each = local.job_ns == local.watch ? ["controller-lease/loadbalancer*"] : []
            labels   = [path.value]

            content {
              capabilities = ["list", "read", "write"]
            }
          }

          # The tokens of the registered classes.
          dynamic "path" {
            for_each = local.tokens == local.watch ? [var.class_token_path] : []
            labels   = [path.value]

            content {
              capabilities = ["read"]
            }
          }
        }

        # The LoadBalancer objects: status, event log and the cleanup
        # finalizer; "write" for the objects of marked services.
        object "norca.io/LoadBalancer" {
          capabilities = local.acl_object_capabilities
        }

        # The registered load balancer classes (cluster-scoped).
        dynamic "object" {
          for_each = local.all ? ["norca.io/LoadBalancerClass"] : []
          labels   = [object.value]

          content {
            capabilities = ["read"]
          }
        }
      }
    }

    # The namespace of the controller job: the leases of its instances.
    dynamic "namespace" {
      for_each = local.job_ns == local.watch ? [] : [local.job_ns]
      labels   = [namespace.value]

      content {
        capabilities = local.all ? local.acl_capabilities : null

        variables {
          dynamic "path" {
            for_each = local.all ? ["nomad/jobs/lb-*"] : []
            labels   = [path.value]

            content {
              capabilities = ["list", "read", "write", "destroy"]
            }
          }

          path "controller-lease/loadbalancer*" {
            capabilities = ["list", "read", "write"]
          }

          dynamic "path" {
            for_each = local.tokens == local.job_ns ? [var.class_token_path] : []
            labels   = [path.value]

            content {
              capabilities = ["read"]
            }
          }
        }

        dynamic "object" {
          for_each = local.all ? ["norca.io/LoadBalancer"] : []
          labels   = [object.value]

          content {
            capabilities = local.acl_object_capabilities
          }
        }
      }
    }

    # The namespace of the tokens of the registered classes.
    dynamic "namespace" {
      for_each = local.tokens == local.watch || local.tokens == local.job_ns ? [] : [local.tokens]
      labels   = [namespace.value]

      content {
        capabilities = local.all ? local.acl_capabilities : null

        variables {
          dynamic "path" {
            for_each = local.all ? ["nomad/jobs/lb-*"] : []
            labels   = [path.value]

            content {
              capabilities = ["list", "read", "write", "destroy"]
            }
          }

          dynamic "path" {
            for_each = [var.class_token_path]
            labels   = [path.value]

            content {
              capabilities = ["read"]
            }
          }
        }

        dynamic "object" {
          for_each = local.all ? ["norca.io/LoadBalancer"] : []
          labels   = [object.value]

          content {
            capabilities = local.acl_object_capabilities
          }
        }
      }
    }

    # The registered load balancer classes are cluster-scoped: their rule is
    # in the namespace "*".
    dynamic "namespace" {
      for_each = local.all ? [] : ["*"]
      labels   = [namespace.value]

      content {
        object "norca.io/LoadBalancerClass" {
          capabilities = ["read"]
        }
      }
    }

    # The nodes of the instances: an instance on a node marked as leaving
    # (norca.lb.leaving, set by the node scaling operator before a drain) is
    # not a target; node events reconcile the load balancers.
    node {
      policy = "read"
    }
  }

  job_acl {
    namespace = rigger.namespace
    job_id    = var.job_name
  }
}
