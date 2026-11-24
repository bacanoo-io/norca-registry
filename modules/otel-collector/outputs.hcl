# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "otlp" {
  value       = var.otlp_enabled ? { grpc = var.otlp_grpc_port, http = var.otlp_http_port } : null
  description = "The OTLP ports of the collector on every node; null without OTLP."
}

output "notes" {
  value = join("\n", concat(
    [
      "OpenTelemetry Collector \"${local.job}\" on every node${var.node_pool != "" ? " of the node pool ${var.node_pool}" : ""}, exporting to OpenObserve (${var.openobserve_endpoint != "" ? var.openobserve_endpoint : "service ${var.openobserve_service}"}, TLS ${var.openobserve_tls}) with the credentials of ${var.ingest_secret_path}.",
      "",
      "Sources:",
    ],
    var.hostmetrics_enabled ? ["  host metrics${var.host_root_volume != "" ? " (host volume ${var.host_root_volume} = / read-only on every node)" : ""}"] : [],
    var.nomad_metrics_enabled ? ["  Norca agent: ${var.nomad_address}/v1/metrics (telemetry { prometheus_metrics = true } on the agents)"] : [],
    length(var.discovery_namespaces) > 0 ? [join("", concat(
      ["  catalog of the namespaces ${join(", ", var.discovery_namespaces)}, instances on the node only:"],
      var.nats_metrics_enabled ? [" ${var.nats_metrics_service}"] : [],
      var.forgejo_metrics_enabled ? [" ${var.forgejo_service} (tag metrics)"] : [],
      var.mtls_gateway_metrics_enabled ? [" ${var.mtls_gateway_metrics_service}"] : [],
      var.consul_metrics_enabled ? [" ${var.consul_metrics_service}"] : [],
    ))] : [],
    var.postgres_metrics_enabled ? ["  PostgreSQL: service ${var.postgres_service} in the namespace of the job, role ${var.postgres_user}"] : [],
    var.otlp_enabled ? ["  OTLP of the applications: <node address>:${var.otlp_grpc_port} (gRPC), :${var.otlp_http_port} (HTTP)"] : [],
    [
      "",
      "Checks:",
      "  norca job status -namespace ${rigger.namespace} ${local.job}",
      "  norca alloc logs -namespace ${rigger.namespace} -task collector <alloc ID>",
    ],
  ))
  description = "The sources of the collector and how to check it."
}
