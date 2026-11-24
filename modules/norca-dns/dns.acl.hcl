# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The permissions of norca-dns, bound to its job.
policy "dns" {
  enabled = var.acl_policy_enabled

  name        = var.job_name
  description = "Permissions of norca-dns (bound to its job)"

  rules {
    # The records are namespaced: the operator reads them in every
    # namespace, writes their status and events, and keeps its finalizer on
    # them. It reads the metadata of the namespaces (their allow lists), the
    # load balancers a record takes its addresses from, and the DNS zones
    # norca-provider registers (cluster scoped).
    namespace "*" {
      capabilities = ["read-job"]

      object "norca.io/DNSRecord" {
        capabilities = ["read", "write-status", "write-events", "manage-finalizers"]
      }

      object "norca.io/LoadBalancer" {
        capabilities = ["read"]
      }

      object "norca.io/DNSZone" {
        capabilities = ["read"]
      }
    }

    # The tokens of the DNS zones. A block of a namespace by name takes the
    # place of the "*" block for that namespace, so it names a capability of
    # its own: without one the operator could not read the metadata of this
    # namespace (its allow list), and no record of it would be written. Any
    # capability lets the namespace be read; list-jobs is the narrowest.
    dynamic "namespace" {
      for_each = [var.zone_token_namespace]
      labels   = [namespace.value]

      content {
        capabilities = ["list-jobs"]

        variables {
          dynamic "path" {
            for_each = [var.zone_token_path]
            labels   = [path.value]

            content {
              capabilities = ["read"]
            }
          }
        }
      }
    }
  }

  job_acl {
    namespace = rigger.namespace
    job_id    = var.job_name
  }
}
