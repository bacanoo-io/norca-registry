[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $ns := "" ]][[ if ne $v.namespace "" ]][[ $ns = printf " -namespace %s" $v.namespace ]][[ end ]]
OpenTelemetry Collector "[[ $job ]]" on every node[[ if ne $v.node_pool "" ]] of the node pool [[ $v.node_pool ]][[ end ]], exporting to OpenObserve ([[ if ne $v.openobserve_endpoint "" ]][[ $v.openobserve_endpoint ]][[ else ]]service [[ $v.openobserve_service ]][[ end ]], TLS [[ $v.openobserve_tls ]]) with the credentials of [[ $v.ingest_secret_path ]].

Sources:
[[- if $v.hostmetrics_enabled ]]
  host metrics[[ if ne $v.host_root_volume "" ]] (host volume [[ $v.host_root_volume ]] = / read-only on every node)[[ end ]]
[[- end ]]
[[- if $v.nomad_metrics_enabled ]]
  Norca agent: [[ $v.nomad_address ]]/v1/metrics (telemetry { prometheus_metrics = true } on the agents)
[[- end ]]
[[- if $v.discovery_namespaces ]]
  catalog of the namespaces [[ join ", " $v.discovery_namespaces ]], instances on the node only:
[[- if $v.nats_metrics_enabled ]] [[ $v.nats_metrics_service ]][[ end ]]
[[- if $v.forgejo_metrics_enabled ]] [[ $v.forgejo_service ]] (tag metrics)[[ end ]]
[[- if $v.mtls_gateway_metrics_enabled ]] [[ $v.mtls_gateway_metrics_service ]][[ end ]]
[[- if $v.consul_metrics_enabled ]] [[ $v.consul_metrics_service ]][[ end ]]
[[- end ]]
[[- if $v.postgres_metrics_enabled ]]
  PostgreSQL: service [[ $v.postgres_service ]] in the namespace of the job, role [[ $v.postgres_user ]]
[[- end ]]
[[- if $v.otlp_enabled ]]
  OTLP of the applications: <node address>:[[ $v.otlp_grpc_port ]] (gRPC), :[[ $v.otlp_http_port ]] (HTTP)
[[- end ]]

Checks:
  norca job status[[ $ns ]] [[ $job ]]
  norca alloc logs[[ $ns ]] -task collector <alloc ID>
