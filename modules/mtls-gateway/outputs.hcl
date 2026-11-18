# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = var.service_name
  description = "The gateway service in the native catalog, in the default namespace."
}

output "notes" {
  value       = <<-EOT
    mTLS gateway "${var.job_name}" (${var.job_type} job, namespace default, region ${rig.region}): service ${var.service_name} on port ${var.port} of every ${local.system ? "eligible node" : "gateway node (${var.count} instances)"}.
    ${var.envoy_task_enabled ? "Envoy task defined by the module: ${var.envoy_driver}${local.container ? ", image ${var.envoy_image != "" ? var.envoy_image : "from the node meta norca.mtls.envoy_*"}" : ", binary ${var.envoy_binary}"}." : "The servers inject the Envoy task mtls-gateway-${var.service_name} (image from the node meta norca.mtls.envoy_*)."}

    Checks:
      norca job status -region ${rig.region} ${var.job_name}
      norca service info -region ${rig.region} -verbose ${var.service_name}
  EOT
  description = "How to check the gateway."
}
