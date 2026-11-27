# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

output "otlp" {
  value       = var.otlp_enabled ? { grpc = var.otlp_grpc_port, http = var.otlp_http_port } : null
  description = "The OTLP ports of the collector on every node; null without OTLP."
}

output "agent_otlp_endpoint" {
  value       = var.nomad_otlp_enabled ? "127.0.0.1:${var.nomad_otlp_port}" : null
  description = "The endpoint of the agents' otlp block in the OTLP mode (nomad_otlp_enabled); null in the scrape mode."
}

output "notes" {
  value = join("\n", concat(
    [
      "OpenTelemetry Collector \"${local.job}\" on every node${var.node_pool != "" ? " of the node pool ${var.node_pool}" : ""}, exporting to OpenObserve (${var.openobserve_endpoint != "" ? var.openobserve_endpoint : "service ${var.openobserve_service}"}, TLS ${var.openobserve_tls}) with the credentials of ${var.ingest_secret_path}.",
      "",
      "Sources:",
    ],
    var.hostmetrics_enabled ? ["  host metrics${var.host_root_volume != "" ? " (host volume ${var.host_root_volume} = / read-only on every node)" : ""}"] : [],
    local.agent_scrape ? ["  Norca agent: ${var.nomad_address}/v1/metrics (telemetry { prometheus { enabled = true } } on the agents)"] : [],
    var.nomad_otlp_enabled ? ["  Norca agent: OTLP/gRPC on 127.0.0.1:${var.nomad_otlp_port} (telemetry { otlp {} } on the agents, endpoint 127.0.0.1:${var.nomad_otlp_port})"] : [],
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
