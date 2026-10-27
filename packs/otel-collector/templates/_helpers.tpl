[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* Checks the variables the schema can't express. */ -]]
[[- define "otel.validate" -]]
[[- $v := vars . -]]
[[- if and $v.otlp_enabled (eq $v.otlp_grpc_port $v.otlp_http_port) ]][[ fail "otlp_grpc_port must differ from otlp_http_port" ]][[ end -]]
[[- if and (eq $v.openobserve_tls "secret") (eq $v.openobserve_ca_secret_path "") ]][[ fail "openobserve_tls = \"secret\" needs openobserve_ca_secret_path" ]][[ end -]]
[[- if not (or $v.otlp_enabled $v.hostmetrics_enabled $v.self_metrics_enabled $v.nomad_metrics_enabled) -]]
[[- fail "enable at least one of otlp_enabled, hostmetrics_enabled, self_metrics_enabled, nomad_metrics_enabled" -]]
[[- end -]]
[[- end -]]

[[- /* The nomad_sd_configs of a discovery scrape job: the catalog of every
discovery namespace, read with the workload identity of the task. */ -]]
[[- define "otel.sd" ]]
[[- $v := vars . ]]
                    nomad_sd_configs:
[[- range $ns := $v.discovery_namespaces ]]
                      - server: [[ $v.nomad_address | quote ]]
                        namespace: [[ $ns | quote ]]
                        refresh_interval: 60s
                        authorization:
                          credentials_file: /secrets/nomad_token
[[- if ne $v.nomad_ca_secret_path "" ]]
                        tls_config:
                          ca_file: /secrets/nomad-ca.pem
[[- end ]]
[[- end ]]
[[- end -]]

[[- /* Relabeling of a discovery scrape job (dict "service" <name>): the service,
the instances on this node only, and the Norca labels. */ -]]
[[- define "otel.sd_relabel" ]]
                    relabel_configs:
                      - source_labels: [__meta_nomad_service]
                        regex: [[ .service | quote ]]
                        action: keep
                      - source_labels: [__meta_nomad_node_id]
                        regex: $${env:NODE_ID}
                        action: keep
                      - source_labels: [__meta_nomad_namespace]
                        target_label: nomad_namespace
                      - source_labels: [__meta_nomad_service]
                        target_label: nomad_service
[[- end -]]

[[- /* The configuration of the collector (a Nomad template: {{ }} is
consul-template, $${env:...} the collector's environment). */ -]]
[[- define "otel.config" -]]
[[- $v := vars . ]]
[[- $sd := and $v.discovery_namespaces (or $v.nats_metrics_enabled $v.forgejo_metrics_enabled $v.mtls_gateway_metrics_enabled $v.consul_metrics_enabled) ]]
[[- $scrapes := or $v.self_metrics_enabled $v.nomad_metrics_enabled $sd ]]
[[- $ooScheme := "https" ]][[ if eq $v.openobserve_tls "none" ]][[ $ooScheme = "http" ]][[ end ]]
[[- $nomadURL := urlParse $v.nomad_address ]]
          extensions:
            health_check:
              endpoint: $${env:NOMAD_IP_health}:$${env:NOMAD_PORT_health}
            basicauth/openobserve:
              client_auth:
                username: $${env:OO_USERNAME}
                password: $${env:OO_PASSWORD}

          receivers:
[[- if $v.otlp_enabled ]]
            # The applications of the node send OTLP here.
            otlp:
              protocols:
                grpc:
                  endpoint: $${env:NOMAD_IP_otlp_grpc}:$${env:NOMAD_PORT_otlp_grpc}
                http:
                  endpoint: $${env:NOMAD_IP_otlp_http}:$${env:NOMAD_PORT_otlp_http}
[[- end ]]
[[- if $v.hostmetrics_enabled ]]
            host_metrics:
              collection_interval: [[ $v.collection_interval ]]
[[- if ne $v.host_root_volume "" ]]
              root_path: /hostfs
[[- end ]]
              scrapers:
                cpu: {}
                memory: {}
                load: {}
                disk: {}
                filesystem: {}
                network: {}
                paging: {}
[[- end ]]
[[- if $scrapes ]]
            prometheus:
              config:
                global:
                  scrape_interval: [[ $v.collection_interval ]]
                scrape_configs:
[[- if $v.self_metrics_enabled ]]
                  - job_name: otel-collector
                    static_configs:
                      - targets: ["127.0.0.1:$${env:NOMAD_PORT_telemetry}"]
[[- end ]]
[[- if $v.nomad_metrics_enabled ]]
                  # The Norca agent of this node (/v1/metrics needs no ACL token).
                  - job_name: norca
                    metrics_path: /v1/metrics
                    params:
                      format: [prometheus]
                    scheme: [[ $nomadURL.scheme ]]
[[- if ne $v.nomad_ca_secret_path "" ]]
                    tls_config:
                      ca_file: /secrets/nomad-ca.pem
[[- end ]]
                    static_configs:
                      - targets: [[ list $nomadURL.host | toJson ]]
                        labels:
                          norca_node_id: $${env:NODE_ID}
[[- end ]]
[[- if and $sd $v.nats_metrics_enabled ]]
                  # The NATS exporters of the nats pack on this node.
                  - job_name: nats
[[- template "otel.sd" . ]]
[[- template "otel.sd_relabel" (dict "service" $v.nats_metrics_service) ]]
[[- end ]]
[[- if and $sd $v.forgejo_metrics_enabled ]]
                  # Forgejo with metrics_enabled (tag metrics) on this node; HTTPS
                  # for the instances tagged https.
                  - job_name: forgejo
                    authorization:
                      credentials: $${env:FORGEJO_METRICS_TOKEN:-none}
                    tls_config:
                      server_name: [[ $v.forgejo_tls_server_name | quote ]]
[[- template "otel.sd" . ]]
[[- template "otel.sd_relabel" (dict "service" $v.forgejo_service) ]]
                      - source_labels: [__meta_nomad_tags]
                        regex: ".*,metrics,.*"
                        action: keep
                      - source_labels: [__meta_nomad_tags]
                        regex: ".*,https,.*"
                        target_label: __scheme__
                        replacement: https
[[- end ]]
[[- if and $sd $v.mtls_gateway_metrics_enabled ]]
                  # The Envoy statistics of the mTLS gateways on this node.
                  - job_name: mtls-gateway
                    metrics_path: /stats/prometheus
[[- template "otel.sd" . ]]
[[- template "otel.sd_relabel" (dict "service" $v.mtls_gateway_metrics_service) ]]
[[- end ]]
[[- if and $sd $v.consul_metrics_enabled ]]
                  # The Consul agent of this node, on 127.0.0.1 (with TLS its
                  # plain HTTP port listens only there).
                  - job_name: consul
                    metrics_path: /v1/agent/metrics
                    params:
                      format: [prometheus]
                    authorization:
                      credentials: $${env:CONSUL_METRICS_TOKEN:-anonymous}
[[- template "otel.sd" . ]]
[[- template "otel.sd_relabel" (dict "service" $v.consul_metrics_service) ]]
                      - source_labels: [__meta_nomad_service_port]
                        target_label: __address__
                        replacement: 127.0.0.1:$$1
[[- end ]]
[[- end ]]
[[- if $v.postgres_metrics_enabled ]]
            # The PostgreSQL instances of the catalog on this node.
            {{- range $i, $s := nomadService "[[ $v.postgres_service ]]" }}{{ if eq $s.Node (env "node.unique.id") }}
            postgresql/{{ $i }}:
              endpoint: {{ $s.Address }}:{{ $s.Port }}
              transport: tcp
              username: [[ $v.postgres_user | quote ]]
              password: $${env:PG_MONITORING_PASSWORD:-unset}
              collection_interval: [[ $v.collection_interval ]]
              tls:
[[- if eq $v.postgres_tls "none" ]]
                insecure: true
[[- else if eq $v.postgres_tls "require" ]]
                insecure_skip_verify: true
[[- else ]]
                insecure_skip_verify: true
                ca_file: /secrets/mtls/bundle.pem
[[- end ]]
            {{- end }}{{ end }}
[[- end ]]

          processors:
            memory_limiter:
              check_interval: 1s
              limit_percentage: 80
              spike_limit_percentage: 20
            resource:
              attributes:
                - key: host.name
                  value: $${env:NODE_NAME}
                  action: insert
                - key: norca.node.id
                  value: $${env:NODE_ID}
                  action: insert
            batch: {}

          exporters:
            otlp_http/openobserve:
              # OpenObserve's OTLP/HTTP endpoints: <endpoint>/v1/{traces,metrics,logs}.
[[- if ne $v.openobserve_endpoint "" ]]
              endpoint: [[ trimSuffix "/" $v.openobserve_endpoint ]]/api/$${env:OO_ORG}
[[- else ]]
              {{- with nomadService "[[ $v.openobserve_service ]]" }}{{ with index . 0 }}
              endpoint: [[ $ooScheme ]]://{{ .Address }}:{{ .Port }}/api/$${env:OO_ORG}
              {{- end }}{{ else }}
              # No instance of [[ $v.openobserve_service ]] yet: the collector retries until the
              # configuration is reloaded with one.
              endpoint: [[ $ooScheme ]]://127.0.0.1:1/api/$${env:OO_ORG}
              {{- end }}
[[- end ]]
              auth:
                authenticator: basicauth/openobserve
              tls:
[[- if eq $v.openobserve_tls "none" ]]
                insecure: true
[[- else if eq $v.openobserve_tls "mtls" ]]
                ca_file: /secrets/mtls/bundle.pem
                server_name_override: $${env:OO_SERVER_NAME}
[[- else if eq $v.openobserve_tls "secret" ]]
                ca_file: /secrets/openobserve-ca.pem
                server_name_override: $${env:OO_SERVER_NAME}
[[- else ]]
                server_name_override: $${env:OO_SERVER_NAME}
[[- end ]]

          service:
            extensions: [health_check, basicauth/openobserve]
            telemetry:
              logs:
                level: [[ $v.log_level ]]
              metrics:
[[- if $v.self_metrics_enabled ]]
                readers:
                  - pull:
                      exporter:
                        prometheus:
                          host: 127.0.0.1
                          port: $${env:NOMAD_PORT_telemetry}
[[- else ]]
                level: none
[[- end ]]
            pipelines:
[[- $receivers := list ]]
[[- if $v.otlp_enabled ]][[ $receivers = append $receivers "otlp" ]][[ end ]]
[[- if $v.hostmetrics_enabled ]][[ $receivers = append $receivers "host_metrics" ]][[ end ]]
[[- if $scrapes ]][[ $receivers = append $receivers "prometheus" ]][[ end ]]
              metrics:
                receivers: [[ "[" ]][[ join ", " $receivers ]][[ if $v.postgres_metrics_enabled ]]{{ range $i, $s := nomadService "[[ $v.postgres_service ]]" }}{{ if eq $s.Node (env "node.unique.id") }}, postgresql/{{ $i }}{{ end }}{{ end }}[[ end ]][[ "]" ]]
                processors: [memory_limiter, resource, batch]
                exporters: [otlp_http/openobserve]
[[- if $v.otlp_enabled ]]
              traces:
                receivers: [otlp]
                processors: [memory_limiter, resource, batch]
                exporters: [otlp_http/openobserve]
              logs:
                receivers: [otlp]
                processors: [memory_limiter, resource, batch]
                exporters: [otlp_http/openobserve]
[[- end ]]
[[- end -]]
