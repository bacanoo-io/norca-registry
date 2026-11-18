# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The permissions of the LoadBalancer operator, bound to its controller job.
policy "controller" {
  enabled = var.acl_policy_enabled

  name        = var.job_name
  description = "Permissions of the LoadBalancer operator (bound to its controller job)"
  rules       = "${local.acl_rules}\n"

  job_acl {
    namespace = rig.namespace
    job_id    = var.job_name
  }
}
