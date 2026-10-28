<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# rustfs

[RustFS](https://rustfs.com), an S3-compatible object store, as the store of
the scheduled Norca backups
([backup and restore](https://github.com/bacanoo-io/norca/blob/main/docs/design/backup-restore-plan.md)):
one server with one drive, or a distributed cluster with one server per node,
the root credentials from Norca's built-in secret store, the data on a client
host volume, health checks with the startup, readiness and liveness roles,
and optionally a poststart task that creates the backup bucket.

Keep the backups outside the cluster they protect: run the store in another
region or cluster than the servers whose backups it keeps, or use an external
S3 store in production. Any S3-compatible store works the same way.

## License and image

RustFS is **Apache-2.0** software by the RustFS team
([LICENSE](https://github.com/rustfs/rustfs/blob/main/LICENSE)). Norca does
not ship it: the pack references the official image, and the nodes pull it.

| | |
| --- | --- |
| Default image | `docker.io/rustfs/rustfs:1.0.1` (release [1.0.1](https://github.com/rustfs/rustfs/releases/tag/1.0.1), 2026-10-03) |
| Index digest | `sha256:1803faef57627e2d9c2e7d89d655d712ddded5389040054987163043fecb6a3c` (linux/amd64, linux/arm64) |
| Container user | `10001:10001` (`rustfs`) |

Pin the digest with `image_digest`, and mirror the image into your internal
registry for air-gapped clusters (`image`). The pack is tested with the image
above; newer releases may change variables or health endpoints.

## Prerequisites

On every node that runs a server:

```hcl
client {
  host_volume "rustfs" {
    path      = "/srv/rustfs"
    read_only = false
  }
}
```

```shell
sudo install -d -o 10001 -g 10001 -m 750 /srv/rustfs   # the container user owns the drive
```

(or set `user` to the owner of the directory). The root credentials live in
the built-in secret store, in the namespace of the job; they are never pack
variables. Values on the command line end up in the shell history: read the
secret key from standard input.

```shell
norca secret put rustfs/root access_key=norca-backup secret_key=-   # type the secret key, then Ctrl-D
```

## Install

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=<tag>
norca pack run rustfs --registry=norca --var='buckets=["norca-backup"]'
norca service info -verbose rustfs
```

From a checkout of this registry: `norca pack run ./packs/rustfs -f examples/rustfs/single-node.hcl`.
Example variable files are in [`examples/rustfs`](../../examples/rustfs).

### The backup bucket

Norca never creates its backup bucket. Either let the pack create it, with
`buckets = ["norca-backup"]`: a poststart task (the RustFS image, with its
curl) waits until the store is ready and sends an S3 CreateBucket signed with
AWS SigV4 for every bucket that does not exist yet; or create it by hand,
with curl 7.75 or newer:

```shell
curl --aws-sigv4 "aws:amz:us-east-1:s3" --user "norca-backup:<secret key>" \
  -X PUT http://<node address>:9000/norca-backup
```

### The Norca backup configuration

In the `server` block of the region whose backups the store keeps:

```hcl
backup {
  enabled  = true
  schedule = "0 * * * *"

  destination "rustfs" {
    type             = "s3"
    endpoint         = "http://<node address>:9000"
    bucket           = "norca-backup"
    prefix           = "norca/${region}"
    region           = "us-east-1"   # s3_region of the pack
    force_path_style = true          # RustFS serves path-style requests

    # AWS shared credentials file with the values of the secret rustfs/root:
    #   [default]
    #   aws_access_key_id     = norca-backup
    #   aws_secret_access_key = <secret key>
    credentials_file = "/etc/norca.d/backup-credentials"
  }

  encryption {
    recipients = ["age1..."]
  }
}
```

`norca config validate` checks the block; `norca operator backup save` runs a
backup at once and waits for its upload and verification.

## Distributed mode

```hcl
mode  = "distributed"
nodes = ["10.0.1.11", "10.0.1.12", "10.0.1.13", "10.0.1.14"]
```

One server runs on each node of `nodes` (a `set_contains_any` constraint on
`node_address_attribute`, `${attr.unique.network.ip-address}` by default, and
`distinct_hosts`), every server lists all of them in `RUSTFS_VOLUMES`
(`http://<node>:<s3_port>/data`) and finds its own endpoint through
`RUSTFS_LOCAL_ENDPOINT_HOST`. The erasure coding spreads every object over the
drives of all servers: use at least 4 nodes to survive the loss of one. The
servers must reach each other on `s3_port`, all of them use the same root
credentials (the secret), and the job keeps one server down at a time at
most (`disruption { max_unavailable = "1" }`, updates one by one). The list of
nodes can't change for an existing cluster; expanding it with another server
pool is not covered by the pack. Use the address of any server (or several,
behind a load balancer) as the backup endpoint.

## Variables

| Variable | Default | |
| --- | --- | --- |
| `job_name` | `""` | empty: `rustfs`; also the name of the service (`<job>`, `<job>-console`) |
| `namespace`, `region` | `""` | empty: those of the release |
| `datacenters`, `node_pool`, `constraints` | `["*"]`, `""`, `[]` | placement |
| `mode` | `single` | `single` or `distributed` |
| `nodes`, `node_address_attribute` | `[]`, `${attr.unique.network.ip-address}` | distributed mode |
| `image`, `image_digest` | `docker.io/rustfs/rustfs:1.0.1`, `""` | the image, optionally pinned by digest |
| `user` | `""` | container user; empty: `10001:10001` of the image |
| `resources` | `{cpu = 500, memory = 1024}` | per server |
| `log_level` | `warn` | logs go to the task's stdout |
| `extra_env` | `{}` | further `RUSTFS_*` settings (never credentials) |
| `host_volume` | `rustfs` | client host volume, mounted at `/data` |
| `s3_port` | `9000` | static S3 port on the node and in the container |
| `console_enabled`, `console_port` | `false`, `9001` | the web console |
| `host_network` | `""` | client host network of the ports |
| `s3_region` | `us-east-1` | `RUSTFS_REGION`; the `region` of the backup destination |
| `secret_path` | `rustfs/root` | secret with the items `access_key` and `secret_key` |
| `buckets` | `[]` | buckets the poststart task creates |
| `startup_timeout`, `healthy_deadline` | `3m`, `10m` | startup check, updates |
| `metrics_enabled`, `traces_enabled`, `otlp_endpoint` | `false`, `false`, `http://${attr.unique.network.ip-address}:4318` | OTLP export, see [Metrics](#metrics) |

The values are checked against the `validation` blocks and rules of
[`variables.hcl`](variables.hcl) before rendering; the servers check the
`validation` blocks again.

## Health checks

| Role | Check |
| --- | --- |
| startup | `GET /health/live` every 5 s, for at most `startup_timeout` |
| readiness | `GET /health/ready` every 10 s: storage, IAM and lock quorum; 503 until the server is ready |
| liveness | `GET /health/live` every 15 s |

The console service (with `console_enabled`) has a readiness check on
`/rustfs/console/health`.

## Metrics

RustFS 1.0.1 has **no Prometheus endpoint** (its `io-metrics` crate says so
explicitly; the `/minio/v2/metrics` paths of MinIO don't exist). It exports
its metrics, traces and logs only by pushing OTLP/HTTP (protobuf, gzip). With
`metrics_enabled = true` the pack sets `RUSTFS_OBS_METRIC_ENDPOINT` to
`<otlp_endpoint>/v1/metrics` (a per-signal endpoint, used as it is, so only
metrics are exported) and `RUSTFS_OBS_SERVICE_NAME` to the job name;
`traces_enabled` adds `RUSTFS_OBS_TRACE_ENDPOINT`. No log endpoint is set, so
the logs keep going to the task's stdout.

The default `otlp_endpoint` is the OpenTelemetry Collector of the
[otel-collector pack](../otel-collector/README.md) on the same node
(`http://${attr.unique.network.ip-address}:4318`, its OTLP/HTTP host port),
which forwards the metrics to OpenObserve. If the collector binds its OTLP
ports to another host network, set `otlp_endpoint` to that address. Without
a collector on the node the export fails quietly (RustFS logs the errors and
keeps serving S3). Metrics are off by default so that existing installations
keep their jobs unchanged.

## Limitations

- Plain HTTP: the S3 API carries the backups (encrypted with age by the Norca
  servers before they leave them) and the credentials (signed requests, the
  secret key is not sent). Keep the store on a private network or the VPN; TLS
  of RustFS (`RUSTFS_TLS_PATH`) is not set up by the pack.
- Docker only.
- One drive per server (the host volume).
- The checks of this registry render and validate the jobs of both modes; the
  pack has not been run against a live cluster yet (the distributed mode in
  particular).
