<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# otel-collector

The [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) on
every node of a Norca cluster (a system job), shipping to
[OpenObserve](../openobserve/README.md):

- **metrics of the node and the platform**, on by default: the host, the
  Norca agent, and the NATS, Forgejo, mTLS gateway, Consul and PostgreSQL
  instances of the node, found through the native catalog;
- an **OTLP receiver on every node** (gRPC 4317, HTTP 4318) for the traces,
  metrics and logs of the applications (APM);
- export over **OTLP/HTTP** with the ingest credentials the openobserve pack
  writes into the built-in secret store, over TLS that trusts **Norca's CA**
  (the collector's own workload identity) by default.

## License and image

The collector is **Apache-2.0** software of the OpenTelemetry project. Norca
does not ship it: the pack references the official image of the contrib
distribution, and the nodes pull it.

| | |
| --- | --- |
| Default image | `docker.io/otel/opentelemetry-collector-contrib:0.162.0` (release [v0.162.0](https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.162.0), 2026-09-29) |
| Index digest | `sha256:39923a8e431bd1f57be82411999d389fcfe40857492e4365456d97a4c1f74be6` (linux/amd64, arm64 and more) |
| Image | `FROM scratch`, `/otelcol-contrib`, user `10001:10001`, no shell |

The contrib distribution contains every component the pack uses (checked in
its `manifest.yaml` at v0.162.0): the receivers `otlp`, `host_metrics`,
`prometheus` (with all Prometheus service discoveries, `nomad_sd_configs`
among them) and `postgresql`; the processors `memory_limiter`, `resource`,
`batch`; the exporter `otlp_http`; the extensions `health_check` and
`basicauth`. The pack uses the component names of this release
(`host_metrics`, `otlp_http`; the old names are deprecated aliases). Pin the
digest with `image_digest`; mirror the image for air-gapped clusters.

## Prerequisites

1. **The openobserve pack, in the same namespace**: the collector reads the
   secret `ingest_secret_path` (`openobserve/ingest`) its bootstrap task
   writes, and finds OpenObserve as the catalog service `openobserve_service`
   of its namespace. The task waits up to 15 minutes for the secret.
2. **The agents' Prometheus metrics** (`telemetry { prometheus_metrics = true }`
   in the configuration of every agent):

   ```hcl
   telemetry {
     prometheus_metrics         = true
     publish_allocation_metrics = true
     publish_node_metrics       = true
   }
   ```

3. **The host's root directory as a host volume** on every client, read-only,
   for the host metrics (the Docker driver does not mount host paths unless
   its `volumes` are enabled; a host volume needs no driver change):

   ```hcl
   client {
     host_volume "hostfs" {
       path      = "/"
       read_only = true
     }
   }
   ```

   Without it set `host_root_volume = ""`: cpu, memory and load are still the
   host's (the kernel's view), the filesystems and disks those of the
   container.
4. **The agent's HTTPS**: with `tls { http = true }` set `nomad_address =
   "https://127.0.0.1:4646"` and put the CA of the agent certificates into the
   secret store (`nomad_ca_secret_path`, item `ca`): `norca tls cert create`
   certificates carry `127.0.0.1` and `localhost`.
5. Docker on the nodes; the collector runs with host networking.

## Install

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=<tag>
norca secret put -namespace observability norca/agent-ca ca=@/etc/norca.d/tls/nomad-agent-ca.pem
norca pack run otel-collector --registry=norca -f examples/otel-collector/observability.hcl
norca job status -namespace observability otel-collector
```

Example variable files are in [`examples/otel-collector`](../../examples/otel-collector).

## What it collects

Every collector scrapes only what runs on **its own node**: the services of
the catalog are filtered by the node ID of the instance
(`__meta_nomad_node_id`, compared with `${node.unique.id}` of the task).

| Source | Variable (default) | How | Needs |
| --- | --- | --- | --- |
| Host | `hostmetrics_enabled` (on) | `host_metrics` receiver, `root_path: /hostfs`: cpu, memory, load, disk, filesystem, network, paging (no per-process metrics, they need root) | the `hostfs` host volume |
| Norca agent | `nomad_metrics_enabled` (on) | Prometheus scrape of `<nomad_address>/v1/metrics?format=prometheus`: servers, clients, allocations, the jobs of the node | `telemetry { prometheus_metrics = true }`; **no ACL token** (the endpoint has no ACL check in Nomad 1.6.5/Norca) |
| NATS | `nats_metrics_enabled` (on) | service `nats-metrics` (the exporter of the nats pack, `metrics_enabled = true` there): `/metrics` | nats-server has no Prometheus endpoint, hence the exporter |
| RustFS | (rustfs pack: `metrics_enabled`) | RustFS 1.0.1 has no Prometheus endpoint; it **pushes** OTLP/HTTP to the OTLP receiver of the collector of its node | `otlp_enabled` (on) |
| Forgejo | `forgejo_metrics_enabled` (on) | service `forgejo` with the tag `metrics` (`metrics_enabled` of the forgejo pack): `/metrics` with `Authorization: Bearer` from the secret `forgejo/metrics` (item `token`, optional); HTTPS for instances tagged `https` (`forgejo_tls_server_name`) | |
| mTLS gateway | `mtls_gateway_metrics_enabled` (on) | service `mtls-gateway-metrics` (`metrics_enabled` of the mtls-gateway pack, with `envoy_task_enabled`): Envoy's `/stats/prometheus` | the injected Envoy has no admin interface |
| Consul | `consul_metrics_enabled` (on) | service `consul-metrics` (`metrics_enabled` of the consul pack): `127.0.0.1:<port>/v1/agent/metrics?format=prometheus` with the token of the secret `consul/metrics` (`agent:read`, optional) | |
| PostgreSQL | `postgres_metrics_enabled` (on) | `postgresql` receiver (OpenObserve's documented way) for every instance of the catalog service `postgres` on the node, as the role `monitoring` (`pg_monitor`) with the password of `postgres/monitoring` (optional) | the monitoring role of the postgres pack |
| The collector | `self_metrics_enabled` (on) | its own metrics on `127.0.0.1` and a dynamic port | |

The sources that need another pack's option cost nothing when it is off: no
service, no target. Secrets marked optional may be missing; the scrape then
fails with an authentication error instead of holding up the collector.

**Discovery** uses the Prometheus receiver's `nomad_sd_configs` against the
local agent (`nomad_address`), one per namespace of `discovery_namespaces`
(`["default"]`; add the namespaces of your NATS, Forgejo, gateway and Consul
jobs), authenticated with the collector's workload identity (`identity { file
= true }`, sent as `Authorization: Bearer`; a workload identity may read the
service registrations of any namespace). PostgreSQL is found with
`nomadService` in the template of the configuration, which sees only the
namespace of the job: run the postgres pack in the same namespace (it is in
the same namespace as OpenObserve in cluster mode anyway). A changed instance
re-renders the configuration and reloads the collector (SIGHUP).

**PostgreSQL TLS** (`postgres_tls`): the `postgresql` receiver's default
without a `tls` block is `sslmode=require`, which fails against a server
without TLS (OpenObserve's troubleshooting page warns about it); the pack
sets it explicitly:

| `postgres_tls` | postgres pack | receiver |
| --- | --- | --- |
| `none` (default) | `tls_mode = "none"` | `tls: {insecure: true}` (`sslmode=disable`) |
| `require` | any TLS | `insecure_skip_verify: true` (`sslmode=require`: encrypted, not verified) |
| `verify-ca` | `tls_mode = "mtls"` | `insecure_skip_verify: true` plus the trust bundle as `ca_file` (`sslmode=require` with a root certificate, which lib/pq checks like `verify-ca`): the CA is verified, the name can't be (the receiver connects to the address and refuses `server_name_override`) |

## OTLP for the applications

With `otlp_enabled` (default) every collector listens on the node address
(`host_network`) on `otlp_grpc_port` (4317) and `otlp_http_port` (4318), the
services `<job>-otlp-grpc` and `<job>-otlp-http`. Applications send to the
collector of their own node:

```hcl
env {
  OTEL_EXPORTER_OTLP_ENDPOINT = "http://${attr.unique.network.ip-address}:4318"
  OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
  OTEL_SERVICE_NAME           = "${NOMAD_JOB_NAME}"
}
```

The receiver has no authentication and no TLS: keep the ports on the private
network (`host_network`) and away from the public interface. Traces, metrics
and logs go through `memory_limiter`, `resource` (adds `host.name` and
`norca.node.id` where missing) and `batch` to OpenObserve.

## Export and TLS

The exporter `otlp_http/openobserve` sends to
`<scheme>://<first instance of openobserve_service>/api/<organization>`
(OpenObserve's OTLP/HTTP paths `/v1/traces|metrics|logs`), or
`openobserve_endpoint`, with HTTP basic authentication (`basicauth`
extension) as the service account of the ingest secret; the organization is
its item `organization` unless `openobserve_organization` is set.

| `openobserve_tls` | Trust |
| --- | --- |
| `mtls` (default) | The collector's health service has `mtls { mode = "app" }`: the client issues the collector a workload certificate and the **trust bundle of the region** (`secrets/mtls/bundle.pem`), renewed and rotated automatically. The exporter verifies OpenObserve's workload certificate against it, for the name `openobserve_server_name` (default `<openobserve_service>.service.<namespace>.nomad`, the name the openobserve pack's certificate carries) while connecting to the address of the catalog. The collector itself serves no TLS. |
| `secret` | the CA of `openobserve_ca_secret_path` (item `ca`) |
| `system` | the system CAs of the image (a public certificate) |
| `none` | plain HTTP (`tls_mode = "none"` of the openobserve pack) |

**Renewals and CA rotations** (`mtls`, and `postgres_tls = "verify-ca"`): the
collector reads `ca_file` only when it loads its configuration (in v0.162.0
`reload_interval` reloads certificates and keys, not the CAs of a client), and
it uses only the bundle, not its own certificate. The mtls block therefore sets
`change_mode = "signal"`, `change_signal = "SIGHUP"`, `change_on = "bundle"`:
when a CA joins the trust bundle (a rotation in this region or a federated
one), the client sends SIGHUP and the collector rebuilds its pipelines with the
new bundle, as for a changed configuration; renewals of its own certificate
change nothing. Since pack version 0.1.1; before, a CA rotation made the
exports fail until the collector restarted.

## Variables

| Variable | Default | |
| --- | --- | --- |
| `job_name`, `namespace`, `region` | `""` | empty: `otel-collector`, those of the release |
| `datacenters`, `node_pool`, `constraints` | `["*"]`, `""`, `[]` | which nodes get a collector |
| `image`, `image_digest` | `docker.io/otel/opentelemetry-collector-contrib:0.162.0`, `""` | |
| `resources` | `{cpu = 200, memory = 256}` | per node; `memory_limiter` at 80 % |
| `collection_interval`, `log_level` | `30s`, `info` | |
| `otlp_enabled`, `otlp_grpc_port`, `otlp_http_port`, `host_network` | `true`, `4317`, `4318`, `""` | OTLP of the applications |
| `openobserve_service`, `openobserve_endpoint` | `openobserve`, `""` | |
| `openobserve_tls`, `openobserve_server_name`, `openobserve_ca_secret_path` | `mtls`, `""`, `""` | |
| `openobserve_organization`, `ingest_secret_path` | `""`, `openobserve/ingest` | |
| `hostmetrics_enabled`, `host_root_volume` | `true`, `hostfs` | |
| `nomad_metrics_enabled`, `nomad_address`, `nomad_ca_secret_path` | `true`, `http://127.0.0.1:4646`, `""` | the local agent (metrics and discovery) |
| `discovery_namespaces` | `["default"]` | |
| `nats_metrics_enabled`, `nats_metrics_service` | `true`, `nats-metrics` | |
| `forgejo_metrics_enabled`, `forgejo_service`, `forgejo_metrics_secret_path`, `forgejo_tls_server_name` | `true`, `forgejo`, `forgejo/metrics`, `forgejo.internal` | |
| `mtls_gateway_metrics_enabled`, `mtls_gateway_metrics_service` | `true`, `mtls-gateway-metrics` | |
| `consul_metrics_enabled`, `consul_metrics_service`, `consul_metrics_secret_path` | `true`, `consul-metrics`, `consul/metrics` | |
| `postgres_metrics_enabled`, `postgres_service`, `postgres_user`, `postgres_secret_path`, `postgres_tls` | `true`, `postgres`, `monitoring`, `postgres/monitoring`, `none` | |
| `self_metrics_enabled` | `true` | |

The values are checked against [`values.schema.json`](values.schema.json)
before rendering and again by the servers.

## Health checks

The `health_check` extension on a dynamic port of the node address: startup
(`GET /`, at most 2 minutes) and liveness (`GET /`, restart after 3 failures).
A system job has no deployments to wait for readiness, so there is no
readiness check.

## Limitations

- Rendered and validated by the checks of this registry, and the rendered
  configuration parsed as YAML; not yet loaded by a running collector or run
  against a live cluster.
- Only the instances on the collector's own node are scraped; components on
  nodes without a collector (another node pool) are not.
- PostgreSQL is discovered in the namespace of the job only.
- The OTLP receiver is unauthenticated plain text on the node address.
- No per-process host metrics (they need root in the container).
