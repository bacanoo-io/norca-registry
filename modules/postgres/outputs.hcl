# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The server in the native catalog (tag tls with TLS)."
}

output "databases" {
  value       = { for d in var.databases : d.name => { user = d.user, secret = d.secret_path } }
  description = "The databases by name: their owner and the secret of its password."
}

output "notes" {
  value = join("\n", concat(
    [
      "PostgreSQL \"${local.job}\": one server, port ${var.port} on its node, service ${local.job} in the native catalog${local.tls ? ", TLS (${var.tls_mode}${var.tls_required ? ", required" : ""})" : ""}; data on the host volume ${var.host_volume}.",
      "",
      "Secrets it reads (create them before the first start):",
      "  norca secret put -namespace ${rigger.namespace} ${var.superuser_secret_path} password=-",
    ],
    [for d in var.databases : "  norca secret put -namespace ${rigger.namespace} ${d.secret_path} password=-      # role ${d.user}, database ${d.name}"],
    var.monitoring_enabled ? ["  norca secret put -namespace ${rigger.namespace} ${var.monitoring_secret_path} password=-      # role ${var.monitoring_user} (pg_monitor)"] : [],
    var.tls_mode == "secret" ? ["  norca secret put -namespace ${rigger.namespace} ${var.tls_secret_path} cert=@postgres.pem key=@postgres-key.pem"] : [],
    var.dump_enabled ? ["  norca secret put -namespace ${rigger.namespace} ${var.dump_storage_secret_path} access_key=<access key> secret_key=-"] : [],
    [
      "",
      "Checks:",
      "  norca job status -namespace ${rigger.namespace} ${local.job}",
      "  norca service info -namespace ${rigger.namespace} -verbose ${local.job}",
    ],
    local.setup ? ["  norca alloc logs -namespace ${rigger.namespace} -task setup <alloc ID>     # the roles and databases"] : [],
    [
      "",
      "Clients in the namespace find the server with nomadService \"${local.job}\" in a template",
      "(or ${local.job}.service.<namespace>.norca through the built-in DNS).",
      "",
      var.dump_enabled ? "Dumps: periodic job ${local.job}-dump (${var.dump_cron} UTC) into ${var.dump_bucket}/${var.dump_prefix}." : "No dumps: Norca's backups don't cover the data of PostgreSQL. Set dump_enabled (or back up otherwise).",
    ],
  ))
  description = "The secrets to create and how clients find the server."
}
