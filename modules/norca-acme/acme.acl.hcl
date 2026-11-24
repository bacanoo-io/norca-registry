# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The permissions of norca-acme, bound to its job.
policy "acme" {
  enabled = var.acl_policy_enabled

  name        = var.job_name
  description = "Permissions of norca-acme (bound to its job)"
  rules {
    # The kinds are cluster-scoped: their rules are in the namespace "*". The
    # operator reads the issuers and the orders the servers write, writes the
    # status of the issuers that name it and of their orders, and reads the
    # DNS zones norca-provider registers. It reads no secret of any other
    # path: the keys of the certificates stay with the servers.
    namespace "*" {
      object "norca.io/CertificateIssuer" {
        capabilities = ["read", "write-status"]
      }

      object "norca.io/CertificateOrder" {
        capabilities = ["read", "write-status"]
      }

      object "norca.io/DNSZone" {
        capabilities = ["read"]
      }
    }

    # The secrets of the operator: the keys of its accounts, the
    # certificates it issued (for a revocation), an external account
    # binding; and the tokens of the DNS zones and the lease of the leader
    # election when they are in the same namespace (locals.hcl).
    dynamic "namespace" {
      for_each = [rigger.namespace]
      labels   = [namespace.value]

      content {
        dynamic "secret" {
          for_each = ["${var.secret_prefix}*"]
          labels   = [secret.value]

          content {
            capabilities = ["read-secret", "write-secret"]
          }
        }

        dynamic "variables" {
          for_each = length(local.variable_grants_here) > 0 ? [local.variable_grants_here] : []

          content {
            dynamic "path" {
              for_each = variables.value
              labels   = [path.value.path]

              content {
                capabilities = path.value.capabilities
              }
            }
          }
        }
      }
    }

    # The tokens of the DNS zones, or the lease, in a namespace of their
    # own.
    dynamic "namespace" {
      for_each = local.variable_grants_elsewhere
      labels   = [namespace.key]

      content {
        variables {
          dynamic "path" {
            for_each = namespace.value
            labels   = [path.value.path]

            content {
              capabilities = path.value.capabilities
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
