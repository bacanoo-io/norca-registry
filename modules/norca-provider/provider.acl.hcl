# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The permissions of norca-provider, bound to its job.
policy "provider" {
  enabled = var.acl_policy_enabled

  name        = var.job_name
  description = "Permissions of norca-provider (bound to its job)"
  rules       = <<-EOT
    # The registrations of the providers are cluster-scoped objects: their rules
    # are in the namespace "*". The provider writes the spec and the status
    # (the heartbeat) of its NodeProvider, LoadBalancerClass and DNSZone objects,
    # and deletes them when it stops. The secrets of the job's own Variable need no
    # rule.
    namespace "*" {
      object "norca.io/NodeProvider" {
        capabilities = ["read", "write", "write-status"]
      }

      object "norca.io/LoadBalancerClass" {
        capabilities = ["read", "write", "write-status"]
      }

      object "norca.io/DNSZone" {
        capabilities = ["read", "write", "write-status"]
      }
    }
  EOT

  job_acl {
    namespace = rig.namespace
    job_id    = var.job_name
  }
}
