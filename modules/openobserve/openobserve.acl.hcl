# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The tasks of the job: the bootstrap task stores the ingest credentials.
policy "openobserve" {
  enabled = var.acl_policy_enabled && var.bootstrap_enabled

  name        = local.job
  description = "Tasks of the OpenObserve job ${local.job} (openobserve pack): ingest credentials"
  rules       = <<-EOT
    namespace "${rig.namespace}" {
      # The bootstrap task stores the token of the ingest service account.
      secret "${var.ingest_secret_path}" {
        capabilities = ["read-secret", "write-secret"]
      }
    }
  EOT

  job_acl {
    namespace = rig.namespace
    job_id    = local.job
  }
}
