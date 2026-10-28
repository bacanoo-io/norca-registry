<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# postgres

A single [PostgreSQL](https://www.postgresql.org) server for the
infrastructure of a Norca cluster (the metadata store of OpenObserve in
cluster mode, small internal services): the data on a client host volume, the
superuser, application databases with their owner roles and a read-only
monitoring role, all with passwords from Norca's built-in secret store, health
checks with roles, a disruption budget, the service `postgres` in the native
catalog, optional TLS with Norca's workload certificates and optional periodic
dumps to S3 (the RustFS of the [rustfs pack](../rustfs/README.md)).

**Out of scope:** replication, failover, connection pooling and point-in-time
recovery. A lost node means a restore from the last dump; for production data
that needs high availability, use a managed PostgreSQL or a PostgreSQL
operator and give its clients the address (e.g. `postgres_endpoint` of the
openobserve pack).

## License and image

PostgreSQL is released under the **PostgreSQL License**, a liberal open
source license similar to BSD/MIT ([license](https://www.postgresql.org/about/licence/)).
Norca does not ship it: the pack references the official Docker image, and
the nodes pull it.

| | |
| --- | --- |
| Default image | `docker.io/library/postgres:18.6` (PostgreSQL 18.6, Debian trixie; the tag exists since 2026-08-13) |
| Index digest | `sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336` (the build of 2026-10-06; the official images are rebuilt often, the tag moves to newer builds of the same release) |
| Container user | `999:999` (`postgres`); the Alpine variant (`18.6-alpine`) uses `70:70` |
| Data | the host volume at `/var/lib/postgresql`; PostgreSQL 18 images keep the data directory in `/var/lib/postgresql/18/docker` (one directory per major version) |

Pin the digest with `image_digest`, and mirror the image for air-gapped
clusters (`image`). PostgreSQL 15 or newer is needed (the setup task uses the
`\getenv` command of psql). PostgreSQL 17 images keep their data in
`/var/lib/postgresql/data`, also below the mount. A new **major** version
does not start on the data of the old one: dump and restore (or `pg_upgrade`)
it; minor versions (18.x) are a plain image change.

## Prerequisites

The host volume on the one PostgreSQL node, owned by the container user (the
pack runs the image as `uid:gid`, so the entrypoint does not change owners):

```hcl
client {
  host_volume "postgres" {
    path      = "/srv/postgres"
    read_only = false
  }
}
```

```shell
sudo install -d -o 999 -g 999 -m 700 /srv/postgres
```

## Secrets

All in the namespace of the job, never in pack variables. Values on the
command line end up in the shell history: type them on standard input.

| Secret | Items | Used by |
| --- | --- | --- |
| `superuser_secret_path` (`postgres/superuser`) | `password` | the image at the first start (`POSTGRES_PASSWORD_FILE`, rendered with mode 0400 for the container user), the setup and dump tasks (`PGPASSWORD`) |
| `secret_path` of each entry of `databases` | `password` | the owner role of the database |
| `monitoring_secret_path` (`postgres/monitoring`) | `password` | the monitoring role (`pg_monitor`); the otel-collector pack reads the same secret |
| `tls_secret_path` (`postgres/tls`, `tls_mode = "secret"`) | `cert`, `key` | the server certificate |
| `dump_storage_secret_path` (`postgres/dump-storage`, dumps) | `access_key`, `secret_key` | the S3 upload |

```shell
norca secret put postgres/superuser password=-
norca secret put postgres/openobserve password=-
norca secret put postgres/monitoring password=-
```

The superuser password is set by `initdb` at the first start only (the image
behaviour): a new version of the secret does not change it in an existing
database. Change it with `ALTER ROLE postgres PASSWORD '...'` and then put the
new version (the setup and dump tasks use the secret). The passwords of the
application and monitoring roles are set again by the setup task at every
start, so for them a new secret version plus a restart of the job is enough.

## Install

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=<tag>
norca pack run postgres --registry=norca -f postgres.hcl
norca service info -verbose postgres
norca alloc logs -task setup <alloc ID>     # "role openobserve and database openobserve ready"
```

From a checkout of this registry: `norca pack run ./packs/postgres -f examples/postgres/openobserve.hcl`.
Example variable files are in [`examples/postgres`](../../examples/postgres).

### Databases and roles

```hcl
databases = [
  { name = "openobserve", user = "openobserve", secret_path = "postgres/openobserve" },
]
```

The poststart task `setup` (the same image, psql) waits until the server
accepts connections, then for each entry creates the login role if it does
not exist, sets its password from the secret (`ALTER ROLE ... PASSWORD`,
psql variables, never on a command line), and creates the database owned by
it if it does not exist. Existing databases are never dropped or changed;
removing an entry leaves the database and the role in place. Roles and
databases are created over TCP with the superuser, the passwords stored as
SCRAM-SHA-256 hashes.

The image's own `/docker-entrypoint-initdb.d` mechanism runs only on an empty
data directory; the setup task covers new entries and rotated passwords of an
existing installation as well, which is why the pack uses it instead.

### Monitoring

With `monitoring_enabled` (the default) the setup task creates the role
`monitoring_user` (`monitoring`) with the predefined role `pg_monitor`
(read-only access to the statistics views), password from
`monitoring_secret_path`. The secret is optional: without it the role is
skipped with a message in the task log, and the next start creates it.
The [otel-collector pack](../otel-collector/README.md) scrapes the server with
the `postgresql` receiver of the OpenTelemetry Collector (the way OpenObserve
documents PostgreSQL monitoring) using this role and the same secret.

## TLS

| `tls_mode` | Certificate |
| --- | --- |
| `none` (default) | plain connections |
| `mtls` | Norca's workload certificate: the service gets `mtls { mode = "app" }`, the client issues a certificate valid for `<job>.service.<namespace>.nomad` (and `<job>.service.<namespace>.<region>.nomad`), signed by the CA of the region, renewed automatically. No sidecar: PostgreSQL terminates TLS itself. |
| `secret` | the PEM certificate (`cert`, with the chain) and key (`key`) of `tls_secret_path` |

PostgreSQL refuses a key file that others can read, so a small start script
copies the certificate and key to `/tmp/tls` (mode 0600) before it starts the
image's entrypoint, and copies them again and reloads the server (SIGHUP; open
connections stay) within a minute after they change: a renewal of the
workload certificate, or a new version of the secret. `mtls { change_mode =
"signal" }` can't replace this watcher: the signal goes to the server, which
would reload the old copies in `/tmp/tls` (the key the client writes into
`secrets/mtls/` is readable by others and must be copied first), and it
wouldn't cover `tls_mode = "secret"`. `tls_required = true`
replaces the image's `pg_hba.conf` with one that allows TCP connections only
over TLS (`hostssl`, SCRAM-SHA-256; the socket inside the container stays
`trust`).

Clients verify the server like this:

- the CA: the trust bundle of the region (`GET /v1/mtls/roots`, or the
  `bundle.pem` that tasks with an mtls service get in `secrets/mtls/`);
- the name: connect by `<job>.service.<namespace>.nomad` (the built-in DNS) and
  use `sslmode=verify-full`. A connection to the IP address of the instance
  (as found through `nomadService`) can only use `sslmode=require` or
  `verify-ca`, because the workload certificates carry DNS names, no IP
  addresses.

The registration carries the meta `norca-mtls = "app"`. Do not use the
service as an `upstream` of an mTLS sidecar: PostgreSQL negotiates TLS inside
its own protocol (SSLRequest), not as plain TLS.

## Dumps

`dump_enabled = true` adds the periodic batch job `<job>-dump`
(`dump_cron`, UTC): `pg_dumpall --clean --if-exists` (every database and the
roles, with their password hashes) compressed with gzip into the allocation
directory, then a poststop task (`dump_upload_image`, curl) uploads it to
`dump_bucket`/`dump_prefix` with an S3 PUT signed with AWS SigV4. The S3 store is the first
instance of `dump_storage_service` (`rustfs`) in the namespace of the job, or
`dump_storage_endpoint`. Create the bucket with the rustfs pack (`buckets`),
give the S3 user write access to it only, and expire old dumps with a
lifecycle rule. The dumps are not encrypted.

Restore (outline): stop the clients, start a server with an empty data
directory, then

```shell
gunzip -c postgres-<time>.sql.gz | norca alloc exec -i -task postgres <alloc ID> psql -U postgres -d postgres
```

## Variables

| Variable | Default | |
| --- | --- | --- |
| `job_name`, `namespace`, `region` | `""` | empty: `postgres`, those of the release |
| `datacenters`, `node_pool`, `constraints` | `["*"]`, `""`, `[]` | placement (the host volume decides the node) |
| `image`, `image_digest` | `docker.io/library/postgres:18.6`, `""` | |
| `uid`, `gid` | `999`, `999` | container user, owner of the volume |
| `resources` | `{cpu = 500, memory = 1024}` | |
| `host_volume` | `postgres` | mounted at `/var/lib/postgresql` |
| `port`, `host_network` | `5432`, `""` | static port on the node |
| `settings` | `{}` | `postgres -c <name>=<value>`, e.g. `max_connections`, `shared_buffers` (no secrets) |
| `superuser`, `superuser_secret_path` | `postgres`, `postgres/superuser` | |
| `databases` | `[]` | `{name, user, secret_path}` entries |
| `monitoring_enabled`, `monitoring_user`, `monitoring_secret_path` | `true`, `monitoring`, `postgres/monitoring` | the `pg_monitor` role |
| `tls_mode`, `tls_secret_path`, `tls_required` | `none`, `postgres/tls`, `false` | |
| `dump_enabled`, `dump_cron`, `dump_bucket`, `dump_prefix` | `false`, `0 2 * * *`, `postgres-dump`, `postgres/` | the dump job |
| `dump_storage_service`, `dump_storage_endpoint`, `dump_storage_use_ssl`, `dump_storage_region`, `dump_storage_secret_path` | `rustfs`, `""`, `false`, `us-east-1`, `postgres/dump-storage` | the S3 store of the dumps |
| `dump_upload_image`, `dump_resources` | `docker.io/curlimages/curl:8.22.0`, `{cpu = 500, memory = 512}` | |
| `startup_timeout`, `healthy_deadline` | `5m`, `10m` | |

The values are checked against the `validation` blocks and rules of
[`variables.hcl`](variables.hcl) before rendering; the servers check the
`validation` blocks again.

## Health checks

Norca's native checks are HTTP or TCP checks; PostgreSQL speaks neither HTTP
nor an open health port, so all three are TCP checks on the server port:

| Role | Check |
| --- | --- |
| startup | TCP every 5 s, at most `startup_timeout` |
| readiness | TCP every 10 s |
| liveness | TCP every 15 s, restart after 3 failures (60 s grace) |

The setup task waits with `pg_isready` before it connects.

## Limitations

- One server, no replication or failover; the disruption budget
  (`min_healthy = 1`) refuses evictions, a drain moves it at its deadline only
  to a node with the same host volume.
- TCP health checks: a server that accepts connections but can't serve
  queries (e.g. during crash recovery) counts as ready.
- `tls_required` replaces the image's `pg_hba.conf`; other access rules need
  your own `hba_file`.
- The pack has been rendered and validated by the checks of this registry,
  not run against a live cluster yet (the setup, TLS reload and dump tasks in
  particular).
