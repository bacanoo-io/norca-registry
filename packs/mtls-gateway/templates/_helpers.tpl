[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* Checks the variables the schema can't express. */ -]]
[[- define "gateway.validate" -]]
[[- $v := vars . -]]
[[- if and $v.envoy_task_enabled (eq $v.envoy_driver "raw_exec") (ne $v.network_mode "host") -]]
[[- fail "envoy_driver = \"raw_exec\" runs outside the network namespace of the group: set network_mode = \"host\"" -]]
[[- end -]]
[[- if and $v.metrics_enabled (not $v.envoy_task_enabled) -]]
[[- fail "metrics_enabled needs envoy_task_enabled = true: the Envoy task the servers inject has no admin interface" -]]
[[- end -]]
[[- end -]]

[[- /* The Envoy arguments of the task defined by the pack, as the servers inject them,
plus the metrics listener merged into the bootstrap (--config-yaml) with metrics_enabled. */ -]]
[[- define "gateway.envoy_args" -]]
[[- $v := vars . -]]
[[- $level := $v.envoy_log_level ]][[ if eq $level "" ]][[ $level = "${meta.norca.mtls.envoy_log_level}" ]][[ end -]]
["-c", "${NOMAD_SECRETS_DIR}/envoy/bootstrap.json", "-l", [[ $level | quote ]], "--disable-hot-restart"[[ if $v.metrics_enabled ]], "--config-yaml", [[ template "gateway.metrics_config" . ]][[ end ]]]
[[- end -]]

[[- /* The metrics configuration merged into the bootstrap written by the client (YAML in
block style: a ${...} reference next to a brace confuses the job parser): the admin
interface on 127.0.0.1 only, and a listener that forwards GET /stats/prometheus (and
nothing else) to it. Verified with Envoy 1.39.3 and 1.40.1. */ -]]
[[- define "gateway.metrics_config" -]]
[[- $v := vars . -]]
[[- $listen := "0.0.0.0" ]][[ if ne $v.network_mode "bridge" ]][[ $listen = "${NOMAD_IP_metrics}" ]][[ end -]]
[[- printf `admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: ${NOMAD_PORT_envoy_admin}
static_resources:
  listeners:
  - name: norca_metrics
    address:
      socket_address:
        address: %s
        port_value: ${NOMAD_PORT_metrics}
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
                port_value: ${NOMAD_PORT_envoy_admin}
` $listen | quote -]]
[[- end -]]
