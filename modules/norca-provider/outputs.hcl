# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "job" {
  value       = var.job_name
  description = "ID of the job and of its service; the ACL policy of the same name is bound to it."
}

output "notes" {
  value       = <<-EOT
    norca-provider "${var.job_name}" in namespace ${rig.namespace}: driver ${var.driver}, port ${var.port}.

    It registers a norca.io/NodeProvider object for every provider with a node
    section and a norca.io/LoadBalancerClass object for every class:
      norca object list norca.io/NodeProvider
      norca object list norca.io/LoadBalancerClass
    %{if var.secrets}
    The secrets of the providers come from the Variable nomad/jobs/${var.job_name}
    (each item is an environment variable of the task, for env:NAME):
      norca var put -namespace ${rig.namespace} nomad/jobs/${var.job_name} PROVIDER_TOKEN=... HCLOUD_TOKEN=...
    %{endif}
    The operators read the token of a provider from its token_variable (item
    token), with the same value as the provider's own token:
      norca var put providers/<name> token=...
  EOT
  description = "How to use the provider."
}
