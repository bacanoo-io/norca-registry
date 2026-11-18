# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

locals {
  system    = var.job_type == "system"
  bridge    = var.network_mode == "bridge"
  container = contains(["docker", "podman"], var.envoy_driver)

  # The Envoy arguments of the task the module defines, as the servers
  # inject them, plus the metrics listener merged into the bootstrap
  # (--config-yaml) with metrics_enabled.
  envoy_level = var.envoy_log_level != "" ? var.envoy_log_level : runtime("meta.norca.mtls.envoy_log_level")
  envoy_args = concat(
    ["-c", "${runtime_env("NORCA_SECRETS_DIR")}/envoy/bootstrap.json", "-l", local.envoy_level, "--disable-hot-restart"],
    var.metrics_enabled ? ["--config-yaml", local.metrics_config] : [],
  )

  # The metrics configuration merged into the bootstrap written by the
  # client (YAML in block style): the admin interface on 127.0.0.1 only,
  # and a listener that forwards GET /stats/prometheus (and nothing else)
  # to it. Verified with Envoy 1.39.3 and 1.40.1.
  metrics_listen = local.bridge ? "0.0.0.0" : runtime_env("NORCA_IP_metrics")
  metrics_config = <<-EOT
    admin:
      address:
        socket_address:
          address: 127.0.0.1
          port_value: ${runtime_env("NORCA_PORT_envoy_admin")}
    static_resources:
      listeners:
      - name: norca_metrics
        address:
          socket_address:
            address: ${local.metrics_listen}
            port_value: ${runtime_env("NORCA_PORT_metrics")}
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: norca_metrics
              route_config:
                virtual_hosts:
                - name: metrics
                  domains: ["*"]
                  routes:
                  - match:
                      path: /stats/prometheus
                    route:
                      cluster: norca_envoy_admin
              http_filters:
              - name: envoy.filters.http.router
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
      clusters:
      - name: norca_envoy_admin
        type: STATIC
        connect_timeout: 1s
        load_assignment:
          cluster_name: norca_envoy_admin
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: 127.0.0.1
                    port_value: ${runtime_env("NORCA_PORT_envoy_admin")}
  EOT
}
