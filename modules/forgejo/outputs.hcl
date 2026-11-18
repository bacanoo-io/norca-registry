# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The HTTP service of Forgejo in the native catalog (tag metrics with metrics_enabled)."
}

output "registry" {
  value       = local.default_port ? var.domain : "${var.domain}:${var.http_port}"
  description = "The address of the container registry."
}

output "notes" {
  value = join("\n", concat(
    [
      "Forgejo \"${local.job}\": ${local.root_url}${var.ssh_enabled ? ", SSH on port ${var.ssh_port}" : ""}; SQLite and the repositories on the host volume ${var.host_volume}${var.storage_enabled ? ", objects in the bucket ${var.storage_bucket}" : ""}.",
      "",
      "Secrets it reads (create them before the first start):",
      "  norca secret put -namespace ${rig.namespace} ${var.keys_secret_path} secret_key=@secret_key internal_token=@internal_token jwt_secret=@jwt_secret lfs_jwt_secret=@lfs_jwt_secret",
    ],
    var.admin_enabled ? ["  norca secret put -namespace ${rig.namespace} ${var.admin_secret_path} password=-"] : [],
    var.storage_enabled ? ["  norca secret put -namespace ${rig.namespace} ${var.storage_secret_path} access_key=<access key> secret_key=-"] : [],
    var.https_enabled ? ["  norca secret put -namespace ${rig.namespace} ${var.tls_secret_path} cert=@forgejo.pem key=@forgejo-key.pem"] : [],
    local.metrics_token ? ["  openssl rand -hex 32 | norca secret put -namespace ${rig.namespace} ${var.metrics_token_secret_path} token=-"] : [],
    [
      "",
      "Checks:",
      "  norca job status -namespace ${rig.namespace} ${local.job}",
      "  norca service info -namespace ${rig.namespace} -verbose ${local.job}",
    ],
    var.admin_enabled ? ["  norca alloc logs -namespace ${rig.namespace} -task create-admin <alloc ID>    # \"admin ${var.admin_username} created\""] : [],
    [
      "",
      "Container images: ${local.default_port ? var.domain : "${var.domain}:${var.http_port}"}/<owner>/<image>:<tag>",
    ],
    var.https_enabled ? [] : [
      "Docker requires HTTPS for a registry on another host: set https_enabled, or put a",
      "TLS-terminating proxy in front of Forgejo (root_url).",
    ],
    [
      "",
      "Next: a pull-only user and token for the nodes, the Docker auth file on every",
      "client (plugin \"docker\" { config { auth { config = \"/etc/norca/docker-auth.json\" } } }),",
      "see the README of the module.",
    ],
    var.dump_enabled ? ["", "Dumps: periodic job ${local.job}-dump (${var.dump_cron} UTC) into ${var.dump_bucket}/${var.dump_prefix}."] : [],
  ))
  description = "The secrets to create and how to use the registry."
}
