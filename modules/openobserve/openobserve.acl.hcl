# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The tasks of the job: the bootstrap task stores the ingest credentials.
policy "openobserve" {
  enabled = var.acl_policy_enabled && var.bootstrap_enabled

  name        = local.job
  description = "Tasks of the OpenObserve job ${local.job} (openobserve pack): ingest credentials"
  rules {
    dynamic "namespace" {
      for_each = [rigger.namespace]
      labels   = [namespace.value]

      content {
        # The bootstrap task stores the token of the ingest service account.
        dynamic "secret" {
          for_each = [var.ingest_secret_path]
          labels   = [secret.value]

          content {
            capabilities = ["read-secret", "write-secret"]
          }
        }
      }
    }
  }

  job_acl {
    namespace = rigger.namespace
    job_id    = local.job
  }
}
