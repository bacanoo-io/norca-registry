# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "service" {
  value       = local.job
  description = "The UI, the API and OTLP/HTTP in the native catalog."
}

output "ingest" {
  value       = { organization = var.ingest_organization, secret = var.ingest_secret_path }
  description = "The organization the collectors write to and the secret of their credentials."
}

output "notes" {
  value = join("\n", concat(
    [
      "OpenObserve \"${local.job}\" (${local.cluster ? "cluster: ${join(", ", [for r in ["router", "ingester", "querier", "compactor", "alertmanager"] : "${var.roles[r].count} ${r}"])}" : "single instance on the host volume ${var.host_volume}"}), TLS ${var.tls_mode}.",
      "",
      "UI and API: ${local.scheme}://<node address of ${local.cluster ? "a router" : "the instance"}>:${var.http_port}/",
    ],
    local.mtls ? [
      "  or ${local.scheme}://${local.job}.service.${rigger.namespace}.nomad:${var.http_port}/ through the built-in DNS. The certificate is",
      "  Norca's workload certificate for that name: browsers trust it once the CA of the",
      "  region is imported (norca operator api /v1/mtls/roots), see the README.",
      "  The client restarts an OpenObserve task after its certificate is renewed or",
      "  the CA rotates (mtls change_mode = \"restart\"): a short interruption of that instance.",
    ] : [],
    [
      "Log in as ${var.root_email} with the password of the secret ${var.root_secret_path}.",
      "OTLP: ${local.scheme}://.../api/${var.ingest_organization}/v1/{logs,metrics,traces} (HTTP), port ${var.grpc_port} (gRPC).",
      "",
      "Secrets it reads (create them before the first start):",
      "  norca secret put -namespace ${rigger.namespace} ${var.root_secret_path} password=-      # 8+ chars, upper and lower case, digit, special character",
    ],
    local.cluster ? concat(
      var.postgres_dsn_secret_path != "" ? ["  norca secret put -namespace ${rigger.namespace} ${var.postgres_dsn_secret_path} dsn=-"] : [
        "  norca secret put -namespace ${rigger.namespace} ${var.postgres_secret_path} password=-      # the postgres module: databases = [{name = \"${var.postgres_database}\", user = \"${var.postgres_user}\", secret_path = \"${var.postgres_secret_path}\"}]",
      ],
      ["  norca secret put -namespace ${rigger.namespace} ${var.s3_secret_path} access_key=<access key> secret_key=-"],
      var.nats_secret_path != "" ? ["  norca secret put -namespace ${rigger.namespace} ${var.nats_secret_path} username=openobserve password=-      # its user of the nats module (auth_mode = \"userpass\"), see the README"] : [],
    ) : [],
    var.tls_mode == "secret" ? ["  norca secret put -namespace ${rigger.namespace} ${var.tls_secret_path} cert=@cert.pem key=@key.pem ca=@ca.pem"] : [],
    var.bootstrap_enabled ? concat(
      [
        "",
        "The bootstrap task stores the ingest credentials of ${var.ingest_service_account} in ${var.ingest_secret_path}:",
        "  norca alloc logs -namespace ${rigger.namespace} -task bootstrap <alloc ID>     # \"ingest credentials ... stored\"",
      ],
      var.acl_policy_enabled ? [] : ["Without the ACL policy of the module, writing the secret needs an agent without ACLs."],
    ) : [],
    [
      "",
      "Checks:",
      "  norca job status -namespace ${rigger.namespace} ${local.job}",
      "  norca service info -namespace ${rigger.namespace} -verbose ${local.job}",
      "",
      "Next: the otel-collector module in the same namespace ships the metrics of every",
      "node and receives OTLP from applications.",
    ],
  ))
  description = "How to reach OpenObserve and the secrets it reads."
}
