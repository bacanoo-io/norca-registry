<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# openobserve

[OpenObserve](https://openobserve.ai) as the observability backend (logs,
metrics, traces: the APM) of a Norca cluster:

- **single mode** (default): one instance with every role, SQLite metadata and
  the data on a client host volume;
- **cluster mode**: a task group per node role (router, ingester, querier,
  compactor, alertmanager) with PostgreSQL metadata (the
  [postgres pack](../postgres/README.md) by default), [NATS](../nats/README.md)
  as the cluster coordinator and the data in S3 (the
  [RustFS](../rustfs/README.md) of the registry);
- **TLS** on HTTP and gRPC with Norca's workload certificates (native mTLS app
  mode) unless a certificate is given;
- the **root user** from the built-in secret store, and an idempotent
  **bootstrap** task that creates the organizations and a **service account
  for the collectors**, and stores its token in the secret store for the
  [otel-collector pack](../otel-collector/README.md).

## License: OpenObserve is AGPL, referenced, never shipped

> **OpenObserve (open source edition) is licensed under the GNU Affero General
> Public License v3.0** ([LICENSE](https://github.com/openobserve/openobserve/blob/v1.0.4/LICENSE)).
> Norca does not distribute, include or modify OpenObserve, and ships no
> binary or image of it. This pack only *references* the official image by
> name, tag and optionally digest; the nodes pull it from Docker Hub (or your
> mirror of the unmodified image). Running it needs no permission; the AGPL's
> obligations apply to those who modify it and offer it to users over a
> network, or distribute it: the source is at
> [github.com/openobserve/openobserve](https://github.com/openobserve/openobserve).

The image is the open source build (no `enterprise` feature): SSO, RBAC with
custom roles and the super cluster are not part of it. The pack itself (these
templates) is MPL 2.0 like the rest of this registry.

## Image

| | |
| --- | --- |
| Default image | `docker.io/openobserve/openobserve:v1.0.4` (also `public.ecr.aws/zinclabs/openobserve:v1.0.4`) |
| Release | [v1.0.4](https://github.com/openobserve/openobserve/releases/tag/v1.0.4), 2026-09-24 (v1.1.0 of 2026-10-14 is less than two weeks old) |
| Index digest | `sha256:d4a878fac1f6c56003764f7f2a1625668917388f167e222c8c810de3f54c56ba` (linux/amd64, linux/arm64; the same on Docker Hub and ECR) |
| Base | `gcr.io/distroless/cc-debian13`: no shell, no curl; runs as root; HTTP on 5080, gRPC on 5081 |

The `-simd` tags are CPU-specific builds; `-debug` adds a shell and tools.
Pin the digest with `image_digest`, and mirror the image for air-gapped
clusters (`image`). The bootstrap task uses
`docker.io/curlimages/curl:8.22.0` (`bootstrap_image`, curl license, Alpine,
user 100), as the OpenObserve image has no shell.

Everything below was checked against the source of v1.0.4
(`src/config/src/config.rs`, the cluster, TLS, gRPC client and HTTP router
code); the pack has been rendered and validated, not run against a live
cluster yet.

## Prerequisites

1. A namespace for the stack, e.g. `observability`, with the collectors in the
   same namespace (they read the ingest secret of this namespace):
   `norca namespace apply observability`.
2. **Single mode**: the host volume on the OpenObserve node (the image runs as
   root, any owner works):

   ```hcl
   client {
     host_volume "openobserve" {
       path      = "/srv/openobserve"
       read_only = false
     }
   }
   ```

3. **Cluster mode**: PostgreSQL, NATS with JetStream and an S3 store, see
   [Cluster mode](#cluster-mode).
4. With ACLs: the release installs an ACL policy bound to the job (see
   [ACL policy](#acl-policy)); the submitter needs `acl:write`, and
   `read-secret` on the secret paths (the `secret_access` grants). On agents
   without ACLs (dev agents) set `acl_policy_enabled = false`.

## Secrets

In the namespace of the job, never in pack variables:

| Secret | Items | |
| --- | --- | --- |
| `root_secret_path` (`openobserve/root`) | `password` | the root user (`ZO_ROOT_USER_PASSWORD`), created at the first start with `root_email`. OpenObserve refuses to start with a weak password: 8–128 characters with a lower-case and an upper-case letter, a digit and a special character. Later changes of the secret don't change the stored password (change it in the UI). |
| `ingest_secret_path` (`openobserve/ingest`) | `username`, `password`, `organization` | **written by the bootstrap task**; read by the otel-collector pack |
| `postgres_secret_path` (`postgres/openobserve`, cluster) | `password` | the role `postgres_user` |
| `postgres_dsn_secret_path` (cluster, optional) | `dsn` | a complete DSN for an external PostgreSQL |
| `s3_secret_path` (`openobserve/s3`, cluster) | `access_key`, `secret_key` | the S3 user |
| `nats_secret_path` (`openobserve/nats`, cluster) | `username`, `password` | OpenObserve's NATS user (nats pack, `auth_mode = "userpass"`); empty path: no NATS authentication |
| `tls_secret_path` (`tls_mode = "secret"`) | `cert`, `key`, `ca` | |

```shell
norca secret put -namespace observability openobserve/root password=-
```

## Install: single mode

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=<tag>
norca pack run openobserve --registry=norca --namespace=observability -f openobserve.hcl
norca service info -namespace observability -verbose openobserve
norca alloc logs -namespace observability -task bootstrap <alloc ID>
```

with e.g. [`examples/openobserve/single.hcl`](../../examples/openobserve/single.hcl).
Then install the [otel-collector pack](../otel-collector/README.md) in the same
namespace.

## Cluster mode

```hcl
mode = "cluster"
```

| Group (`ZO_NODE_ROLE`) | Default count | |
| --- | --- | --- |
| `router` | 2 | the UI and the API; proxies writes to the ingesters and searches to the queriers; static ports `http_port`/`grpc_port`; service `<job>` |
| `ingester` | 2 | writes, WAL, parquet files to S3 |
| `querier` | 2 | searches |
| `compactor` | 1 | merges files, applies the retention (several are possible: NATS locks) |
| `alertmanager` | 1 | alerts, reports, scheduled pipelines (`scheduler` in the source) |

`roles` sets count, cpu and memory per role (every role needs an entry and at
least one instance). Every group runs **with host networking**: an OpenObserve
node advertises to the others exactly the address it binds to
(`ZO_HTTP_ADDR`/`ZO_GRPC_ADDR`, there is no separate advertise address), so the
pack binds it to the node address of a dynamic port (`${NOMAD_IP_http}`,
`${NOMAD_PORT_http}`); only the routers have static ports. Every instance has
a sticky ephemeral disk (`cluster_disk_mb`) for the WAL and caches; with
`ingester_host_volume` the ingesters keep the WAL on a host volume (one per
node). Disruption budgets keep at most one instance of a role down at a time.

### PostgreSQL

OpenObserve v1.0.4 supports only PostgreSQL as the metadata store in cluster
mode (MySQL is rejected by the code, although older documentation mentions
it). By default the pack finds it in the native catalog (`postgres_service`,
`postgres`, in the namespace of the job) and passes host, port, user,
database (`ZO_META_POSTGRES_*`, which OpenObserve URL-encodes into a DSN) and
the password of `postgres_secret_path`. Create the database and its owner with
the postgres pack, in the same namespace:

```hcl
# postgres.hcl
namespace = "observability"
databases = [{ name = "openobserve", user = "openobserve", secret_path = "postgres/openobserve" }]
```

```shell
norca secret put -namespace observability postgres/superuser password=-
norca secret put -namespace observability postgres/openobserve password=-
norca pack run postgres --registry=norca -f postgres.hcl
```

`postgres_endpoint` names a fixed `host:port`, and `postgres_dsn_secret_path`
takes a complete DSN (item `dsn`) of an external PostgreSQL instead.

### NATS

OpenObserve uses NATS (with **JetStream**: KV buckets and streams named
`<nats_prefix><name>`, `o2_` by default, with `nats_replicas` replicas, 3 by
default: at most the number of NATS servers) as coordinator and queue. The
pack lists every instance of the catalog service `nats_service` (`nats`) in
`ZO_NATS_ADDR`, or `nats_endpoints`.

OpenObserve supports **user/password authentication only** (`ZO_NATS_USER`,
`ZO_NATS_PASSWORD`; no token, NKey, credentials file or TLS settings). By
default the pack expects a dedicated NATS user for it from the
[nats pack](../nats/README.md#users-and-accounts-auth_mode--userpass) with
`auth_mode = "userpass"`, in an account of its own, deployed in the same
namespace (the catalog lookup of `nats_service` is per namespace):

```hcl
# nats.hcl (nats pack)
namespace = "observability"
auth_mode = "userpass"
users = [
  { name = "openobserve", account = "OPENOBSERVE" },
  # ... the other users of the NATS cluster
]
```

```shell
# the password, read by the NATS servers (plain, or a bcrypt hash of nats server passwd)
norca secret put -namespace observability nats/users/openobserve password=-
# the same password for OpenObserve (nats_secret_path)
norca secret put -namespace observability openobserve/nats username=openobserve password=-
norca pack run nats --registry=norca -f nats.hcl
```

**Permissions: the account is the boundary.** The user gets no subject
permissions inside its account `OPENOBSERVE`, and the account gives it
nothing outside: its own subjects and its own JetStream, no access to the
streams, KV buckets and subjects of the other accounts (the event stream of
the bridge, applications), and they none to its. A narrower list inside the
account isn't practical, as checked in the v1.0.4 source
(`src/infra/src/db/nats.rs`, `src/infra/src/queue/nats.rs`):

- the coordinator, the locks and the cluster state are JetStream KV buckets
  `<nats_prefix><name>` (`o2_nodes`, `o2_clusters`, `o2_locker`, ... one per
  first key segment, created on first use): `$KV.<bucket>.>` and the
  JetStream API of the streams `KV_<bucket>` (info, create, message get,
  consumers);
- the queues are streams `<nats_prefix><topic>` with the subjects
  `<nats_prefix><topic>` and `<nats_prefix><topic>.*` and durable pull
  consumers;
- the key listing creates ordered push consumers whose deliver subject is a
  random KSUID (a top-level subject of 27 characters, not below `_INBOX`), and
  the statistics list every stream of the account (`$JS.API.STREAM.LIST`).

NATS wildcards match whole tokens only, so `o2_*` can't be expressed as a
subject permission, and the KSUID deliver subjects need a subscribe
permission on every top-level subject: the account isolates OpenObserve
instead. Its JetStream usage counts against the servers' limits
(`jetstream_max_file` / `jetstream_max_memory` of the nats pack).

To run without NATS authentication (a private network, `auth_mode = "none"`)
set `nats_secret_path = ""`.

NATS TLS (`tls_enabled` of the nats pack) can't be used by OpenObserve v1.0.4:
keep the client port on the private network (VPN); the password then travels
in clear text on it.

Changing the password: put the new password into both secrets right after
each other. The NATS servers reload and disconnect OpenObserve's connections
with the old password; OpenObserve restarts with the new one (a new version of
`nats_secret_path` restarts its tasks). For a change without that gap add a
second user (e.g. `openobserve2` in the same account), switch
`nats_secret_path` to it, then remove the first.

### S3

The data goes to `s3_bucket` of the S3 store of the catalog service
`s3_service` (`rustfs`, path-style requests, `ZO_S3_PROVIDER = "s3"`), or
`s3_endpoint`, with the credentials of `s3_secret_path`. OpenObserve does not
create the bucket: the bootstrap task does (`s3_create_bucket`, an S3
CreateBucket signed with SigV4 by curl; an existing bucket is kept). Give
OpenObserve a RustFS user limited to its bucket.

### Install

```shell
norca pack run openobserve --registry=norca -f examples/openobserve/cluster.hcl
```

A change of the PostgreSQL, NATS or S3 instances in the catalog restarts the
nodes (with up to a minute of splay).

## TLS

| `tls_mode` | HTTP (UI, API, OTLP/HTTP) and gRPC |
| --- | --- |
| `mtls` (default) | Norca's workload certificates |
| `secret` | the certificate, key and CA of `tls_secret_path` |
| `none` | plain HTTP and gRPC |

**With Norca's certificates** the services of the job get
`mtls { mode = "app" }`: the client issues every OpenObserve task a
certificate (ECDSA P-256, PKCS #8 key; OpenObserve's rustls loads both) for
the DNS names of the mtls services of its group, renewed automatically, and the
trust bundle of the region, in `secrets/mtls/` (`cert.pem`, `key.pem`,
`bundle.pem`). The certificates carry these names, no IP addresses:

- `<job>.service.<namespace>.nomad` (and `...<region>.nomad`): the instance
  (single) or the routers (cluster): the UI, the API, OTLP;
- `<job>-grpc.service.<namespace>.nomad`: the gRPC service, which every role
  registers, so that every node's certificate carries the name the nodes check
  on internal gRPC calls (`ZO_GRPC_TLS_CERT_DOMAIN`).

The pack sets `ZO_HTTP_TLS_*`/`ZO_GRPC_TLS_*` to these files, and makes the
clients inside OpenObserve trust the region's CA: `*_TLS_ROOT_CERTIFICATES =
native` with `SSL_CERT_DIR=/secrets/mtls` (rustls-native-certs 0.8 adds the
certificates of that directory to the system CAs of `SSL_CERT_FILE`, so
outgoing HTTPS to public services keeps working).

What can't use them, and the alternative taken:

- **The router's HTTP proxy** connects to the advertised IP address of an
  ingester or querier and checks it against the certificate, which names no
  address. In cluster mode `ZO_HTTP_TLS_SKIP_VERIFY = true`: that internal hop
  is encrypted, not verified. Internal gRPC is verified.
- **Certificate renewal**: OpenObserve loads its certificate only at start,
  Norca renews the files at two thirds of their lifetime and re-issues them
  after a CA rotation. The mtls services of the pack set
  `change_mode = "restart"`: the client restarts the `openobserve` task of an
  allocation in place after it has written a renewed certificate or a trust
  bundle with a new CA, and only then. There are no periodic restarts. The
  client coalesces the changes of about a second plus a random splay of up to
  5 seconds, and after a CA rotation the client waits for the re-issued certificate, so
  each rotation or renewal restarts a task once (task event "mTLS certificate
  renewed", "mTLS trust bundle rotated", or both). The restart does not count
  against the restart policy. Every restart is a short interruption of that
  instance (in single mode of the service; collectors retry). Renewals are
  spread over the instances by the client's jitter (about every 16 hours
  with the default `leaf_cert_ttl` of 24h), but a CA rotation (automatic
  after two thirds of the CA's lifetime, or `PUT /v1/mtls/ca/rotate`; also
  that of a federated region, whose CA joins the trust bundle) reaches every
  instance within seconds: all nodes of the job restart within a few seconds
  of each other, a short outage of the whole service. Rotate CAs on request
  at a quiet time. The bootstrap task, which has finished by then, is not
  started again.
- **Health checks**: Norca's native HTTP checks trust only the system CAs and
  connect to the address: with TLS the checks are TCP checks (HTTP checks of
  `/healthz` without TLS).

**Collectors** (the otel-collector pack) trust the CA through their own
workload identity (`bundle.pem`) and verify the name
`<job>.service.<namespace>.nomad` (`server_name_override`), connecting to the
address of the catalog.

**Browsers and other clients**: the certificate is valid for
`https://<job>.service.<namespace>.nomad:<http_port>/`; the built-in DNS
resolves that name (forward `.nomad` to it on the users' machines, or use a
DNS record or `/etc/hosts` entry with that name). Import the CA of the region
into the trust store of the browser or operating system:

```shell
norca operator api /v1/mtls/roots | jq -r '.Roots[].RootCert' > norca-mtls-ca.pem
```

The roots are rotated (every few years, or on demand); import the new one
before the old one leaves the bundle. For users outside the cluster a
TLS-terminating proxy with a public certificate in front of the routers is
usually simpler (`tls_mode = "secret"` or `"none"` behind it), and
`web_url` sets the URL OpenObserve uses in links.

**With a certificate of the secret store** (`secret`): `cert` (with the chain),
`key` and `ca`; in cluster mode every node uses the same certificate, which
must carry `tls_cert_domain` (the gRPC name the nodes verify); a new version
of the secret restarts the tasks. The bootstrap task connects to its own
instance without verification in this mode.

## Bootstrap: root user, organizations, ingest credentials

1. **Root user**: `ZO_ROOT_USER_EMAIL` (`root_email`) and
   `ZO_ROOT_USER_PASSWORD` (the secret). OpenObserve creates the root user
   and the organization `default` when no root user exists.
2. **The bootstrap task** (poststart, `bootstrap_image`; in single mode in the
   instance's group, in cluster mode in every router allocation) runs after
   every start and is idempotent:
   - waits for `/healthz`;
   - cluster: creates `s3_bucket` (200 created, 409 exists);
   - makes sure of every organization of `organizations`: the list
     `GET /api/organizations` (root), and for a missing one a first ingestion
     of one record into the stream `norca_bootstrap` of that organization
     (`POST /api/<org>/norca_bootstrap/_json`): `POST /api/organizations`
     would give the organization a random identifier and is not idempotent;
   - if the stored ingest credentials (`ingest_secret_path`, read as an
     optional secret) work (`GET /api/<org>/streams` → 200): done;
   - otherwise creates the service account `ingest_service_account` in
     `ingest_organization` (`POST /api/<org>/service_accounts`; an existing one
     is kept), issues it a new token (`PUT /api/<org>/service_accounts/<email>?rotateToken=true`,
     root or admin only) and writes `username`, `password` (the token) and
     `organization` into the secret store: `PUT /v1/secret/<path>` through the
     task API socket with its workload identity, which the ACL policy of the
     pack allows. Without that permission it logs the two manual commands
     (rotate the token, `norca secret put`) and fails.

Service accounts and their tokens are part of OpenObserve's open source
edition (`ZO_SERVICE_ACCOUNT_ENABLED`, on by default); a token authenticates
OTLP/HTTP and OTLP/gRPC as `Basic <email>:<token>`. In the open source edition
every user is an admin of its organizations; there are no ingest-only roles.

## ACL policy

`openobserve.acl.hcl.tpl` installs the policy `<job>`, bound to the job
(`job_acl`), in the namespace `namespace` (`default` when empty: set
`namespace` when the release goes to another namespace):

```hcl
namespace "observability" {
  secret "openobserve/ingest" {
    capabilities = ["read-secret", "write-secret"]  # bootstrap
  }
}
```

Bound to the job, it applies to every task of it. It is installed only with
`bootstrap_enabled`; since pack version 0.2.0 it no longer grants
`alloc-lifecycle` (the certificate restarts are done by the client).

## Upgrading from 0.1.x

Pack version 0.2.0 replaces the `tls-restart` sidecar, which restarted the
`openobserve` task every `tls_restart_interval` (6h), with
`mtls { change_mode = "restart" }` (see [TLS](#tls)):

- The upgrade removes a task from every group: a destructive update that
  replaces the allocations one at a time (the `update` block of the groups);
  in single mode a short interruption of the instance.
- Servers and clients must be Norca builds with the change modes of the
  `mtls` block (`change_mode`, `change_signal`, `change_on`): a client
  without them ignores the setting, and OpenObserve would keep its
  certificate until it expires.
- `tls_restart_interval` is still accepted and ignored, so existing variable
  files keep working; the pack output points it out. Remove it from your
  variable files: version 0.3.0 removes the variable.
- The ACL policy of the pack no longer grants `alloc-lifecycle`, and is
  installed only with `bootstrap_enabled`.
- Cluster mode also connects to NATS as its own user by default since 0.2.0
  (`nats_secret_path`, see [NATS](#nats)).

## Variables

| Variable | Default | |
| --- | --- | --- |
| `job_name`, `namespace`, `region` | `""` | empty: `openobserve`, those of the release |
| `datacenters`, `node_pool`, `constraints` | `["*"]`, `""`, `[]` | placement |
| `image`, `image_digest` | `docker.io/openobserve/openobserve:v1.0.4`, `""` | |
| `extra_env` | `{}` | further `ZO_*` settings (no secrets, addresses, roles or TLS; the schema rejects them) |
| `telemetry_enabled`, `web_url` | `false`, `""` | `ZO_TELEMETRY` (OpenObserve's default sends usage data to its vendor), `ZO_WEB_URL` |
| `mode` | `single` | `single` or `cluster` |
| `http_port`, `grpc_port`, `host_network` | `5080`, `5081`, `""` | static ports of the instance or the routers |
| `host_volume`, `resources` | `openobserve`, `{cpu = 1000, memory = 2048}` | single mode |
| `roles`, `cluster_disk_mb`, `ingester_host_volume` | see above, `10240`, `""` | cluster mode |
| `postgres_service`, `postgres_endpoint`, `postgres_database`, `postgres_user`, `postgres_secret_path`, `postgres_dsn_secret_path` | `postgres`, `""`, `openobserve`, `openobserve`, `postgres/openobserve`, `""` | cluster: metadata |
| `nats_service`, `nats_endpoints`, `nats_secret_path`, `nats_replicas`, `nats_prefix` | `nats`, `[]`, `openobserve/nats`, `3`, `o2_` | cluster: coordinator |
| `s3_service`, `s3_endpoint`, `s3_use_ssl`, `s3_bucket`, `s3_region`, `s3_secret_path`, `s3_create_bucket` | `rustfs`, `""`, `false`, `openobserve`, `us-east-1`, `openobserve/s3`, `true` | cluster: data |
| `tls_mode`, `tls_secret_path`, `tls_cert_domain` | `mtls`, `openobserve/tls`, `""` | |
| `tls_restart_interval` | `""` | deprecated and ignored since 0.2.0, removed in 0.3.0 (see [upgrading](#upgrading-from-01x)) |
| `root_email`, `root_secret_path` | `root@openobserve.internal`, `openobserve/root` | |
| `bootstrap_enabled`, `bootstrap_image` | `true`, `docker.io/curlimages/curl:8.22.0` | |
| `organizations`, `ingest_organization`, `ingest_service_account`, `ingest_secret_path` | `["default"]`, `default`, `otel-collector@openobserve.internal`, `openobserve/ingest` | |
| `acl_policy_enabled` | `true` | |
| `startup_timeout`, `healthy_deadline` | `5m`, `10m` | |

The values are checked against [`values.schema.json`](values.schema.json)
before rendering and again by the servers.

## Health checks

| Role | Without TLS | With TLS |
| --- | --- | --- |
| startup | `GET /healthz` every 5 s, at most `startup_timeout` | TCP |
| readiness | `GET /healthz` every 10 s | TCP |
| liveness | `GET /healthz` every 15 s, restart after 3 failures | TCP |

`/healthz` needs no authentication and answers `{"status":"ok"}` once the
HTTP server runs; `/schedulez` (200 only for an online, schedulable node) is
not used, as its meaning for routers is not documented. In cluster mode every
role has its own HTTP service with the checks: `<job>` for the routers,
`<job>-<role>` for the others.

## Limitations

- Not run against a live cluster yet: the bootstrap requests, the cluster
  wiring and the TLS settings are taken from the v1.0.4 source, not from a test.
- TLS with Norca's certificates restarts an instance after every renewal of
  its certificate (OpenObserve can't reload it), and all instances at once
  after a CA rotation.
- The router → node HTTP hop is not verified in cluster mode with TLS.
- NATS: user/password only, no TLS. Since pack version 0.2.0 cluster mode
  expects the user by default (`nats_secret_path = "openobserve/nats"`); set it
  to `""` to keep connecting without authentication.
- Cluster mode keeps no data in PostgreSQL besides the metadata; back up the
  S3 bucket (RustFS replication) and PostgreSQL (the dumps of the postgres
  pack). Single mode: back up the host volume.
- The organizations are created by an ingestion of one record into the stream
  `norca_bootstrap`; delete the stream in the UI if it bothers you.
