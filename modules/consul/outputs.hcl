# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The API of the servers in the native catalog."
}

output "serf_service" {
  value       = "${local.job}-serf"
  description = "The gossip addresses of the servers, the retry_join of the agents."
}

output "notes" {
  value = join("\n", concat(
    [
      "Consul ${var.consul_version} (official HashiCorp release, BSL 1.1 - accepted by you, not distributed by Norca):",
      "  ${local.job}            ${var.server_count} server(s), datacenter ${var.datacenter}, driver ${var.driver}, TLS ${local.tls ? "on" : "off"}, ACL default deny",
    ],
    var.clients_enabled ? ["  ${local.job}-clients    a client agent on every other node (system job)"] : [],
    var.snapshot_enabled ? ["  ${local.job}-snapshot   snapshots to s3://${var.snapshot_s3_bucket}/${var.snapshot_s3_prefix}/${var.datacenter}/ (${var.snapshot_cron} UTC)"] : [],
    split("\n", <<-EOT

      With Norca ACLs enabled, the bootstrap task needs this policy bound to it
      (this is the only manual step). Save it as ${local.job}-bootstrap.hcl and
      apply it before the first run:
        norca acl policy apply -namespace ${rigger.namespace} -job ${local.job} -group servers -task bootstrap \
          ${local.job}-bootstrap ${local.job}-bootstrap.hcl

      namespace "${rigger.namespace}" {
        variables {
          path "nomad/jobs/${local.job}/servers/bootstrap" {
            capabilities = ["read", "write"]
          }
          path "nomad/jobs/${local.job}/servers" {
            capabilities = ["write"]
          }
          path "nomad/jobs/${local.job}-clients" {
            capabilities = ["write"]
          }
          path "nomad/jobs/${local.job}-snapshot/snapshot" {
            capabilities = ["write"]
          }
        }
      }
    EOT
    ),
    [
      "Mark the server nodes (${var.server_count}, one per datacenter${var.server_node_meta != "" ? ", meta ${var.server_node_meta} = \"true\"" : ""})${var.driver != "raw_exec" ? " and give them the host volume \"${var.server_host_volume}\"" : ""}.",
      "",
      "The management token (keep it safe; the CA key is in the same Variable):",
      "  norca var get -namespace ${rigger.namespace} -item=management_token ${local.src_var}",
      "",
      "Check the cluster (any server allocation):",
      "  norca service info -namespace ${rigger.namespace} ${local.job}",
      "  norca alloc exec -namespace ${rigger.namespace} -task server <alloc id> \\",
      "    consul operator raft list-peers -token=<management token>",
    ],
    var.snapshot_enabled && var.snapshot_s3_credentials ? [
      "",
      "The snapshot job reads its S3 credentials from a Variable:",
      "  norca var put -namespace ${rigger.namespace} nomad/jobs/${local.snapshot} aws_access_key_id=<id> aws_secret_access_key=-",
    ] : [],
    var.metrics_enabled ? [
      "",
      "Metrics (service ${local.job}-metrics): the secret ID of the metrics token, read by the",
      "acl-setup task and the otel-collector module (create it before the run):",
      "  cat /proc/sys/kernel/random/uuid | norca secret put -namespace ${rigger.namespace} ${var.metrics_token_secret_path} token=-",
    ] : [],
    [
      "",
      "Connecting the Norca agents to this Consul (optional, not automatic): see the",
      "\"Wiring Norca's consul block\" section of the README.",
    ],
  ))
  description = "The jobs, the one manual step with ACLs, and how to check the cluster."
}
