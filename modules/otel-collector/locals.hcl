# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  # The ID of the job and the name of its service; empty is the release.
  job = coalesce(var.job_name, rig.release)

  # The workload identity serves the mTLS certificate and bundle.
  identity = var.openobserve_tls == "mtls" || var.postgres_tls == "verify-ca"
  hostfs   = var.hostmetrics_enabled && var.host_root_volume != ""

  server_name = var.openobserve_server_name != "" ? var.openobserve_server_name : "${var.openobserve_service}.service.${runtime_env("NORCA_NAMESPACE")}.norca"

  # The secrets the tasks read, after the ingest credentials.
  secret_paths = concat(
    [var.ingest_secret_path],
    var.forgejo_metrics_enabled ? [var.forgejo_metrics_secret_path] : [],
    var.consul_metrics_enabled ? [var.consul_metrics_secret_path] : [],
    var.postgres_metrics_enabled ? [var.postgres_secret_path] : [],
    var.nomad_ca_secret_path != "" ? [var.nomad_ca_secret_path] : [],
    var.openobserve_tls == "secret" ? [var.openobserve_ca_secret_path] : [],
  )

  # The CA files of the tasks, from the secret store.
  ca_files = concat(
    var.nomad_ca_secret_path != "" ? [{ path = var.nomad_ca_secret_path, file = "secrets/nomad-ca.pem" }] : [],
    var.openobserve_tls == "secret" ? [{ path = var.openobserve_ca_secret_path, file = "secrets/openobserve-ca.pem" }] : [],
  )
}

# The configuration of the collector, line by line (a template of the task:
# {{ }} is consul-template, ${env:...} the collector's environment).
locals {
  sd_any  = length(var.discovery_namespaces) > 0 && (var.nats_metrics_enabled || var.forgejo_metrics_enabled || var.mtls_gateway_metrics_enabled || var.consul_metrics_enabled)
  scrapes = var.self_metrics_enabled || var.nomad_metrics_enabled || local.sd_any

  oo_scheme = var.openobserve_tls == "none" ? "http" : "https"
  nomad_url = regex("^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)", var.nomad_address)

  # The nomad_sd_configs of a discovery scrape job: the catalog of every
  # discovery namespace, read with the workload identity of the task.
  sd = concat(["          nomad_sd_configs:"], flatten([for ns in var.discovery_namespaces : concat(
    [
      "            - server: ${jsonencode(var.nomad_address)}",
      "              namespace: ${jsonencode(ns)}",
      "              refresh_interval: 60s",
      "              authorization:",
      "                credentials_file: /secrets/norca_token",
    ],
    var.nomad_ca_secret_path != "" ? ["              tls_config:", "                ca_file: /secrets/nomad-ca.pem"] : [],
  )]))

  # Relabeling of a discovery scrape job by its service: the service, the
  # instances on this node only, and the Norca labels.
  sd_relabel = { for s in [var.nats_metrics_service, var.forgejo_service, var.mtls_gateway_metrics_service, var.consul_metrics_service] : s => [
    "          relabel_configs:",
    "            - source_labels: [__meta_nomad_service]",
    "              regex: ${jsonencode(s)}",
    "              action: keep",
    "            - source_labels: [__meta_nomad_node_id]",
    "              regex: $${env:NODE_ID}",
    "              action: keep",
    "            - source_labels: [__meta_nomad_namespace]",
    "              target_label: nomad_namespace",
    "            - source_labels: [__meta_nomad_service]",
    "              target_label: nomad_service",
  ]... }

  scrape_configs = concat(
    var.self_metrics_enabled ? [
      "        - job_name: otel-collector",
      "          static_configs:",
      "            - targets: [\"127.0.0.1:$${env:NORCA_PORT_telemetry}\"]",
    ] : [],
    var.nomad_metrics_enabled ? concat(
      [
        "        # The Norca agent of this node (/v1/metrics needs no ACL token).",
        "        - job_name: norca",
        "          metrics_path: /v1/metrics",
        "          params:",
        "            format: [prometheus]",
        "          scheme: ${local.nomad_url[0]}",
      ],
      var.nomad_ca_secret_path != "" ? ["          tls_config:", "            ca_file: /secrets/nomad-ca.pem"] : [],
      [
        "          static_configs:",
        "            - targets: ${jsonencode([local.nomad_url[1]])}",
        "              labels:",
        "                norca_node_id: $${env:NODE_ID}",
      ],
    ) : [],
    local.sd_any && var.nats_metrics_enabled ? concat(
      ["        # The NATS exporters of the nats pack on this node.", "        - job_name: nats"],
      local.sd, local.sd_relabel[var.nats_metrics_service][0],
    ) : [],
    local.sd_any && var.forgejo_metrics_enabled ? concat(
      [
        "        # Forgejo with metrics_enabled (tag metrics) on this node; HTTPS",
        "        # for the instances tagged https.",
        "        - job_name: forgejo",
        "          authorization:",
        "            credentials: $${env:FORGEJO_METRICS_TOKEN:-none}",
        "          tls_config:",
        "            server_name: ${jsonencode(var.forgejo_tls_server_name)}",
      ],
      local.sd, local.sd_relabel[var.forgejo_service][0],
      [
        "            - source_labels: [__meta_nomad_tags]",
        "              regex: \".*,metrics,.*\"",
        "              action: keep",
        "            - source_labels: [__meta_nomad_tags]",
        "              regex: \".*,https,.*\"",
        "              target_label: __scheme__",
        "              replacement: https",
      ],
    ) : [],
    local.sd_any && var.mtls_gateway_metrics_enabled ? concat(
      [
        "        # The Envoy statistics of the mTLS gateways on this node.",
        "        - job_name: mtls-gateway",
        "          metrics_path: /stats/prometheus",
      ],
      local.sd, local.sd_relabel[var.mtls_gateway_metrics_service][0],
    ) : [],
    local.sd_any && var.consul_metrics_enabled ? concat(
      [
        "        # The Consul agent of this node, on 127.0.0.1 (with TLS its",
        "        # plain HTTP port listens only there).",
        "        - job_name: consul",
        "          metrics_path: /v1/agent/metrics",
        "          params:",
        "            format: [prometheus]",
        "          authorization:",
        "            credentials: $${env:CONSUL_METRICS_TOKEN:-anonymous}",
      ],
      local.sd, local.sd_relabel[var.consul_metrics_service][0],
      [
        "            - source_labels: [__meta_nomad_service_port]",
        "              target_label: __address__",
        "              replacement: 127.0.0.1:$$1",
      ],
    ) : [],
  )

  receivers = concat(
    var.otlp_enabled ? [
      "  # The applications of the node send OTLP here.",
      "  otlp:",
      "    protocols:",
      "      grpc:",
      "        endpoint: $${env:NORCA_IP_otlp_grpc}:$${env:NORCA_PORT_otlp_grpc}",
      "      http:",
      "        endpoint: $${env:NORCA_IP_otlp_http}:$${env:NORCA_PORT_otlp_http}",
    ] : [],
    var.hostmetrics_enabled ? concat(
      ["  host_metrics:", "    collection_interval: ${var.collection_interval}"],
      var.host_root_volume != "" ? ["    root_path: /hostfs"] : [],
      [
        "    scrapers:",
        "      cpu: {}",
        "      memory: {}",
        "      load: {}",
        "      disk: {}",
        "      filesystem: {}",
        "      network: {}",
        "      paging: {}",
      ],
    ) : [],
    local.scrapes ? concat(
      [
        "  prometheus:",
        "    config:",
        "      global:",
        "        scrape_interval: ${var.collection_interval}",
        "      scrape_configs:",
      ],
      local.scrape_configs,
    ) : [],
    var.postgres_metrics_enabled ? concat(
      [
        "  # The PostgreSQL instances of the catalog on this node.",
        "  {{- range $i, $s := nomadService \"${var.postgres_service}\" }}{{ if eq $s.Node (env \"node.unique.id\") }}",
        "  postgresql/{{ $i }}:",
        "    endpoint: {{ $s.Address }}:{{ $s.Port }}",
        "    transport: tcp",
        "    username: ${jsonencode(var.postgres_user)}",
        "    password: $${env:PG_MONITORING_PASSWORD:-unset}",
        "    collection_interval: ${var.collection_interval}",
        "    tls:",
      ],
      var.postgres_tls == "none" ? ["      insecure: true"] : var.postgres_tls == "require" ? ["      insecure_skip_verify: true"] : ["      insecure_skip_verify: true", "      ca_file: /secrets/mtls/bundle.pem"],
      ["  {{- end }}{{ end }}"],
    ) : [],
  )

  exporter_endpoint = var.openobserve_endpoint != "" ? [
    "    endpoint: ${trimsuffix(var.openobserve_endpoint, "/")}/api/$${env:OO_ORG}",
    ] : [
    "    {{- with nomadService \"${var.openobserve_service}\" }}{{ with index . 0 }}",
    "    endpoint: ${local.oo_scheme}://{{ .Address }}:{{ .Port }}/api/$${env:OO_ORG}",
    "    {{- end }}{{ else }}",
    "    # No instance of ${var.openobserve_service} yet: the collector retries until the",
    "    # configuration is reloaded with one.",
    "    endpoint: ${local.oo_scheme}://127.0.0.1:1/api/$${env:OO_ORG}",
    "    {{- end }}",
  ]

  exporter_tls = {
    none   = ["      insecure: true"]
    mtls   = ["      ca_file: /secrets/mtls/bundle.pem", "      server_name_override: $${env:OO_SERVER_NAME}"]
    secret = ["      ca_file: /secrets/openobserve-ca.pem", "      server_name_override: $${env:OO_SERVER_NAME}"]
  }

  pipeline_receivers = concat(
    var.otlp_enabled ? ["otlp"] : [],
    var.hostmetrics_enabled ? ["host_metrics"] : [],
    local.scrapes ? ["prometheus"] : [],
  )

  config = join("\n", concat(
    [
      "",
      "extensions:",
      "  health_check:",
      "    endpoint: $${env:NORCA_IP_health}:$${env:NORCA_PORT_health}",
      "  basicauth/openobserve:",
      "    client_auth:",
      "      username: $${env:OO_USERNAME}",
      "      password: $${env:OO_PASSWORD}",
      "",
      "receivers:",
    ],
    local.receivers,
    [
      "",
      "processors:",
      "  memory_limiter:",
      "    check_interval: 1s",
      "    limit_percentage: 80",
      "    spike_limit_percentage: 20",
      "  resource:",
      "    attributes:",
      "      - key: host.name",
      "        value: $${env:NODE_NAME}",
      "        action: insert",
      "      - key: norca.node.id",
      "        value: $${env:NODE_ID}",
      "        action: insert",
      "  batch: {}",
      "",
      "exporters:",
      "  otlp_http/openobserve:",
      "    # OpenObserve's OTLP/HTTP endpoints: <endpoint>/v1/{traces,metrics,logs}.",
    ],
    local.exporter_endpoint,
    ["    auth:", "      authenticator: basicauth/openobserve", "    tls:"],
    lookup(local.exporter_tls, var.openobserve_tls, ["      server_name_override: $${env:OO_SERVER_NAME}"]),
    [
      "",
      "service:",
      "  extensions: [health_check, basicauth/openobserve]",
      "  telemetry:",
      "    logs:",
      "      level: ${var.log_level}",
      "    metrics:",
    ],
    var.self_metrics_enabled ? [
      "      readers:",
      "        - pull:",
      "            exporter:",
      "              prometheus:",
      "                host: 127.0.0.1",
      "                port: $${env:NORCA_PORT_telemetry}",
    ] : ["      level: none"],
    [
      "  pipelines:",
      "    metrics:",
      "      receivers: [${join(", ", local.pipeline_receivers)}${var.postgres_metrics_enabled ? "{{ range $i, $s := nomadService \"${var.postgres_service}\" }}{{ if eq $s.Node (env \"node.unique.id\") }}, postgresql/{{ $i }}{{ end }}{{ end }}" : ""}]",
      "      processors: [memory_limiter, resource, batch]",
      "      exporters: [otlp_http/openobserve]",
    ],
    var.otlp_enabled ? [
      "    traces:",
      "      receivers: [otlp]",
      "      processors: [memory_limiter, resource, batch]",
      "      exporters: [otlp_http/openobserve]",
      "    logs:",
      "      receivers: [otlp]",
      "      processors: [memory_limiter, resource, batch]",
      "      exporters: [otlp_http/openobserve]",
    ] : [],
  ))
}
