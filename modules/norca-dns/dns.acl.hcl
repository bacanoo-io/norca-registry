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
      for_each = [local.tokens]
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

          # The lease of the leader election, when the tokens are in the
          # namespace of the job (see below).
          dynamic "path" {
            for_each = local.leader_election && local.tokens_here ? [local.lease_path] : []
            labels   = [path.value]

            content {
              capabilities = ["read", "write"]
            }
          }
        }
      }
    }

    # The lease of the leader election (review finding CON-6e), a Variable
    # of the namespace of the job: every instance reads it, and writes it
    # with check-and-set to take, renew and release the lead. It is never
    # listed or deleted. In a block of its own when the tokens are in
    # another namespace, with a capability for the same reason as above.
    dynamic "namespace" {
      for_each = local.leader_election && !local.tokens_here ? [rigger.namespace] : []
      labels   = [namespace.value]

      content {
        capabilities = ["list-jobs"]

        variables {
          dynamic "path" {
            for_each = [local.lease_path]
            labels   = [path.value]

            content {
              capabilities = ["read", "write"]
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
