# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "plugin_id" {
  value       = var.plugin_id
  description = "The plugin_id of the volumes."
}

output "notes" {
  value       = <<-EOT
    SeaweedFS CSI job "${local.job}": the plugin "${var.plugin_id}" (controller and node) and the mount service on every node, raw_exec; filer ${var.filer != "" ? var.filer : "from the service ${var.filer_service}"}; volume statistics every ${var.stats_interval}.

      norca plugin status ${var.plugin_id}
      norca volume create volume.hcl        # plugin_id = "${var.plugin_id}", see the README of the module
      norca volume status <volume>          # Node Usage: usage and condition reported by the driver
  EOT
  description = "How to use the plugin."
}
