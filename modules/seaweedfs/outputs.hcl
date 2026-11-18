# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "job" {
  value       = local.job
  description = "ID of the job."
}

output "filer_service" {
  value       = "${local.job}-filer"
  description = "The filer in the native catalog: filer_service of the seaweedfs-csi module."
}

output "notes" {
  value       = <<-EOT
    SeaweedFS job "${local.job}": one server (master, volume server, filer) with raw_exec, data in ${var.data_dir}%{if var.node != ""} of ${var.node}%{endif}.

    Services (native discovery):
      ${local.job}-master    http :${var.master_port}   curl http://<addr>/cluster/status
      ${local.job}-volume    http :${var.volume_port}   curl http://<addr>/status
      ${local.job}-filer     http :${var.filer_port}   the filer of the seaweedfs-csi module (filer_service = "${local.job}-filer")
  EOT
  description = "How to reach the server."
}
