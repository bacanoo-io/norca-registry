<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# mtls-gateway

The cross-region gateway of Norca's native mTLS
([usage](https://github.com/bacanoo-io/norca/blob/main/docs/native-mtls.md#cross-region-gateway)):
a group with a service in `gateway` mode (`mtls { mode = "gateway" }`), run in
the `default` namespace of every region that offers services to other
regions. The gateway listens on a static port, reads the SNI name of each TLS
connection and forwards it, without terminating it, to a healthy instance of
the mtls service `<service>.service.<namespace>.<region>.nomad` of its
region. mTLS stays end to end between the sidecars; the intentions of the
destination region decide.

**Envoy is injected by the servers.** The pack renders a group without a task:
when the job is registered, the servers add the Envoy task
`mtls-gateway-<service>` (kind `mtls-gateway:<service>`, the official
`envoyproxy/envoy` image chosen by node meta, 100 MHz / 128 MB), and the
client writes its configuration. With `envoy_task_enabled = true` the pack
defines that task itself (image, binary, resources, log level) and the
servers inject none. Norca does not distribute Envoy; the nodes pull the image
(or run the binary you install). Norca is tested against Envoy 1.39 and 1.40.

## Install

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=<tag>
norca pack run mtls-gateway --registry=norca --region=eu-1
norca pack run mtls-gateway --registry=norca --region=eu-2
# or every region in one release:
norca pack run mtls-gateway --registry=norca --name=mtls-gateway --regions=eu-1,eu-2
```

From a checkout of this registry: `norca pack run ./packs/mtls-gateway`.
`norca pack render mtls-gateway --registry=norca` shows the job without
submitting it. Example variable files are in
[`examples/mtls-gateway`](../../examples/mtls-gateway).

Requirements (see the [usage](https://github.com/bacanoo-io/norca/blob/main/docs/native-mtls.md)):

- native mTLS enabled on the servers of every region, federated trust
  (`server { mtls { federation = true } }`);
- the nodes of the other regions reach `<node address>:<port>` of the gateway
  nodes (for example over the VPN between the clouds; `host_network` binds
  the port to an interface, `constraints` selects the nodes on the VPN);
- with ACLs, a client `dns { token = "..." }` valid in every region (a global
  token with `read-job` on the namespaces of the gateways), so that clients
  can read the catalog of the other region;
- intentions in the destination region for every connection.

An upstream reaches a service of another region through its gateway:

```hcl
mtls {
  mode = "sidecar"
  upstream "api" {
    service    = "api"
    region     = "eu-2"
    local_port = 9090
    # gateway = "<service_name>" when the gateway service is not called mtls-gateway
  }
}
```

## Variables

| Variable | Default | |
| --- | --- | --- |
| `job_name` | `mtls-gateway` | job name; the job always runs in the `default` namespace, where upstreams look for gateways |
| `region` | `""` | empty: the region of the release |
| `datacenters`, `node_pool` | `["*"]`, `""` | placement |
| `job_type` | `system` | `system`: a gateway on every eligible node; `service`: `count` gateways on distinct nodes |
| `count`, `distinct_hosts` | `2`, `true` | `service` jobs only |
| `constraints` | `[]` | extra job constraints (`attribute`, `operator`, `value`) |
| `update_max_parallel` | `1` | gateways replaced at a time |
| `service_name` | `mtls-gateway` | the name upstreams look for by default (`gateway = "<name>"` otherwise) |
| `service_tags` | `[]` | tags of the service |
| `port` | `8443` | static port on the nodes (and in the network namespace) |
| `host_network` | `""` | client host network of the port |
| `network_mode` | `bridge` | `bridge` or `host` |
| `envoy_task_enabled` | `false` | `true`: the pack defines the Envoy task |
| `envoy_driver` | `docker` | `docker`, `podman`, `exec` or `raw_exec` (raw_exec needs `network_mode = "host"`) |
| `envoy_image` | `""` | e.g. `docker.io/envoyproxy/envoy:v1.40.1`; empty: the image of the node meta |
| `envoy_binary` | `/usr/local/bin/envoy` | `exec`, `raw_exec` |
| `envoy_log_level` | `""` | empty: node meta `norca.mtls.envoy_log_level` (default `info`) |
| `envoy_resources` | `{cpu = 100, memory = 128}` | resources of the task defined by the pack |
| `metrics_enabled`, `metrics_port` | `false`, `0` | `/stats/prometheus` of the Envoy task defined by the pack, see [Metrics](#metrics) |

The values are checked against [`values.schema.json`](values.schema.json)
before rendering and again by the servers.

### The Envoy image without the pack

The injected task takes its image from node meta, so air-gapped clusters can
use a mirror and pin a digest without changing the job:

```hcl
client {
  meta {
    "norca.mtls.envoy_registry" = "registry.internal:5000"
    "norca.mtls.envoy_tag"      = "v1.40.1"
    "norca.mtls.envoy_digest"   = "sha256:..."
  }
}
```

## Metrics

The Envoy task the servers inject has no admin interface (native mTLS
disables it), so the gateway has metrics only with `envoy_task_enabled = true`
and `metrics_enabled = true`. The pack then merges a small configuration into
the bootstrap the client writes (`--config-yaml`, which Envoy merges into the
file given with `-c`):

- the admin interface on `127.0.0.1:${NOMAD_PORT_envoy_admin}` only (a dynamic
  port; in bridge mode inside the network namespace of the group);
- a listener on the port `metrics` (dynamic unless `metrics_port`; in host
  mode on the address of the port) whose only route forwards
  `GET /stats/prometheus` to the admin interface; every other path answers
  404, so the mutating admin endpoints (`/quitquitquit`, `/drain_listeners`,
  `/logging`, ...) stay unreachable from outside.

The port is registered as the service `<service_name>-metrics` (tag
`metrics`, no checks), which the [otel-collector pack](../otel-collector/README.md)
finds through the native catalog. Tested with Envoy 1.39.3 and 1.40.1:
`envoy --mode validate` with the bootstrap of a gateway, and a running Envoy
answering 200 with the statistics on `/stats/prometheus` and 404 on `/stats`
and `POST /quitquitquit` through the metrics listener.

## Checks

- `norca job status -region <region> mtls-gateway`: one allocation per
  gateway node, with the task `mtls-gateway-mtls-gateway` (or `envoy`).
- `norca service info -region <region> -verbose mtls-gateway`: the instances
  with the meta `norca-mtls = "gateway"`.
- `norca pack render` and `norca job validate` of the rendered job:
  validation without an agent reports the missing task, as only the servers
  inject it; `norca job plan` or `norca pack plan` against a cluster
  validates the complete job.

## Limitations

- TCP only, like all of native mTLS: no HTTP routing or L7 intentions.
- The gateway forwards to every mtls service of its region; intentions protect
  the services.
- The port is static: two gateways of the same region can't share a node.
- Changing the gateway service (`mtls` block) is a destructive update.
