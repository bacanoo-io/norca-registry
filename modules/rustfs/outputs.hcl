# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The S3 API in the native catalog."
}

output "s3_port" {
  value       = var.s3_port
  description = "The port of the S3 API on the nodes."
}

output "notes" {
  value       = <<-EOT
    RustFS "${local.job}" (${local.distributed ? "distributed, ${length(var.nodes)} servers" : "single server"}) in namespace ${rig.namespace}: S3 API on port ${var.s3_port}${var.console_enabled ? ", console on port ${var.console_port}" : ""}.

    The root credentials come from the secret ${var.secret_path} (items access_key, secret_key):
      norca secret put -namespace ${rig.namespace} ${var.secret_path} access_key=<access key> secret_key=-

    Checks:
      norca job status -namespace ${rig.namespace} ${local.job}
      norca service info -namespace ${rig.namespace} -verbose ${local.job}
    ${length(var.buckets) > 0 ? "\nThe poststart task create-buckets creates: ${join(", ", var.buckets)}." : "\nCreate the backup bucket (S3 CreateBucket, signed by curl 7.75 or newer):\n  curl --aws-sigv4 \"aws:amz:${var.s3_region}:s3\" --user \"<access key>:<secret key>\" \\\n    -X PUT http://<node address>:${var.s3_port}/norca-backup"}

    Backup destination in the server configuration of the region it backs up:
      backup {
        destination "rustfs" {
          type             = "s3"
          endpoint         = "http://<node address>:${var.s3_port}"
          bucket           = "norca-backup"
          prefix           = "norca/$${region}"
          region           = "${var.s3_region}"
          force_path_style = true
          credentials_file = "/etc/norca.d/backup-credentials"
        }
      }
  EOT
  description = "How to use the store."
}
