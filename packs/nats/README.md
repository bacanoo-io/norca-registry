<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# nats

A NATS cluster for one Norca region, and optionally the event stream → NATS
bridge of the region (`nomad/natsbridge` in the Norca repository). In the multi-cloud setup of the
development plan ("Multi-cloud connectivity": one Norca region per cloud,
a VPN between them) the pack is deployed once per region; the gateways join
the regional clusters into a **NATS supercluster**, JetStream keeps durable
streams, and leaf nodes can attach edge sites.

NATS is only the event and notification bridge: nothing in Norca reads from
it, so a NATS outage delays events but does not affect scheduling or
deployments.

## What it deploys

**Job `nats`** (name: `job_name`), one group of `count` servers (default 3):

- one server per node (`distinct_hosts`), optionally spread over datacenters
  (one per availability zone) with the fork's `separate` block
  (`separate_scope`, e.g. `${node.datacenter}`);
- **routes** between the servers, discovered through the `<job>-cluster`
  service with Nomad native service discovery (`nomadService` in the
  configuration template). The service is a group service, so it is
  registered before the tasks start and the servers find each other on their
  first start; a change of the members is applied with `SIGHUP` (reload);
- **JetStream** with a persistent store (see [Storage](#storage));
- **gateway** listener and the list of remote gateways (`gateway_enabled`,
  `remote_gateways`);
- **TLS** on the client, route, gateway and leaf node ports and **client
  authentication** (token, NKeys, or a raw accounts/operator snippet), both
  from a Variable, never inline in the jobspec; or **users in accounts** with
  subject permissions and their passwords in the built-in secret store
  (`auth_mode = "userpass"`, see [Users and accounts](#users-and-accounts-auth_mode--userpass));
- monitoring port with the fork's **health check roles** on the client
  service: `startup` (`/healthz?js-enabled-only=true`, restarts the server if
  it does not come up within `startup_timeout`), `readiness` (`/healthz`:
  JetStream current; deployments and migrations wait for it) and `liveness`
  (restarts a hung server);
- a **`disruption { max_unavailable = 1 }`** block (fork feature): drains and
  evictions take down one server at a time, so the JetStream Raft groups keep
  their majority. Rolling updates (`update`) and migrations (`migrate`) also
  go one server at a time and wait for readiness;
- lame duck shutdown (`kill_signal = "SIGUSR2"`): a stopping server moves its
  clients to the others first.

Services (native provider): `<job>` (clients, with the checks),
`<job>-cluster` (routes, no checks, so not-ready peers are found too),
`<job>-gateway`, `<job>-monitor`, `<job>-leafnode`.

Server names are `<cluster_name>-<alloc index>` (stable across reschedules,
unique in the supercluster); the cluster name, which is also the gateway
name, defaults to the Norca region (`NOMAD_REGION`).

**Job `natsbridge`** (only with `bridge_enabled = true`): the bridge of
`nomad/natsbridge/examples/natsbridge.nomad.hcl`, connected to the client
service of the cluster through `nomadService`, publishing to
`<prefix>.<region>.<topic>` into the JetStream stream
`NORCA_EVENTS_<region>` (`bridge_jetstream_stream`), with
`bridge_jetstream_replicas` replicas (default 1; 3 with servers in three
datacenters, so the events survive the loss of one). With
`bridge_sync_pushes` it also syncs the cluster pack registries of a source when
a push notice arrives on `<prefix>.packs.pushed`, and with
`bridge_sync_regions` it publishes the registry events and syncs a registry
when the one of the same name and source in another region found other packs
(the bridge's inbound mode, see `nomad/natsbridge/README.md` in the Norca
repository). Both need `object "packs.norca.io/Registry"` with `read` and
`write` in the `namespace "*"` block of the bridge's ACL policy; the output of
the pack prints the policy with it.

## Drivers

| `driver` | Server | Notes |
|---|---|---|
| `docker` (default) | official `nats` image (`image`, default `nats:2.15.0`, Apache-2.0) | ports mapped on the node's address |
| `raw_exec` | `binary` on the node, or downloaded with `artifact_url` | no isolation; binds to the node address of `host_network`; host volumes cannot be mounted, use `storage = "path"` |
| `exec` | as `raw_exec`, in the exec chroot (`binary` relative to the task directory with `artifact_url`) | needs a root client |

With `artifact_url`, e.g.

```
--var driver=exec \
--var artifact_url=https://github.com/nats-io/nats-server/releases/download/v2.15.0/nats-server-v2.15.0-linux-amd64.tar.gz \
--var artifact_checksum=sha256:<sha256 of the archive> \
--var binary=local/nats-server-v2.15.0-linux-amd64/nats-server
```

The bridge has no published image: `bridge_driver = "raw_exec"` (default)
or `exec` with `bridge_binary`/`bridge_artifact_url`, or `docker` with your
own `bridge_image`. Build the binary in a Norca checkout with
`cd nomad/natsbridge && go build -o norca-natsbridge ./cmd/norca-natsbridge`.

## Storage

| `storage` | Where | Trade-offs |
|---|---|---|
| `ephemeral_disk` (default) | `alloc/data`, `ephemeral_disk { sticky = true, migrate = true, size = ephemeral_disk_size }` | Nothing to prepare on the nodes. Data survives restarts and in-place replacement on the same node; on a reschedule to another node it is copied only if the old node is reachable. A lost node loses its copy, so use replicated (R3) streams; the replacement server catches up from its peers. Disk size is not enforced as a hard limit: keep `jetstream_max_file` below `ephemeral_disk_size`. |
| `host_volume` | client host volume `host_volume` (docker, exec), subdirectory per server name | Survives everything a node survives; the servers are tied to nodes that have the volume (the scheduler only places them there). Configure the volume on the clients: `client { host_volume "nats" { path = "/srv/nats" } }`. |
| `path` | `store_path` on the node (raw_exec), subdirectory per server name | Like a host volume, without mounting; the directory must exist and be writable by the task user. |

Size the store with `jetstream_max_file` / `jetstream_max_memory`. A server
that moves to another node with an empty store keeps its name and catches up
from the other replicas; a server that disappears for good stays an offline
peer until it is removed (`nats server raft peer-remove <name>`).

## Secrets: TLS and client authentication

The servers read a Variable, by default `nomad/jobs/<job>`, which the job
reads with its workload identity without any ACL policy
(`secrets_variable` changes the path, then bind a policy that allows reading
it). The task does not start until the Variable exists when TLS or
authentication is enabled.

| Item | Used with |
|---|---|
| `tls_ca`, `tls_cert`, `tls_key` | `tls_enabled = true`. The certificate must be valid for server and client authentication (routes and gateways verify each other, mutual TLS) and carry the addresses or names the clients use. |
| `client_token` | `auth_mode = "token"` (plain or a bcrypt hash made with `nats server passwd`; any characters, quoted for the NATS configuration parser) |
| `client_nkeys` | `auth_mode = "nkey"`: public user NKeys (`U...`), comma or newline separated |
| `auth_config` | `auth_mode = "config"`: a raw configuration snippet, e.g. `accounts { ... }` or the `operator`/`system_account`/`resolver` lines of `nsc generate config` for JWT credentials (enable JetStream for the accounts that need it) |

`auth_mode = "userpass"` reads no Variable item: its passwords are in the
secret store, see below (TLS still comes from the Variable).

```
norca var put nomad/jobs/nats \
  tls_ca=@ca.pem tls_cert=@server.pem tls_key=@server-key.pem \
  client_token=<token>
```

Changes of the Variable are applied with a reload (`SIGHUP`). TLS is off by
default so the pack runs on a development agent; across clouds turn it on
(the VPN encrypts the traffic, TLS also authenticates the routes and
gateways). `tls_verify_clients` additionally requires client certificates.
The cluster and gateway ports have no password: keep them reachable only on
the VPN (`host_network`) and use TLS.

## Users and accounts (`auth_mode = "userpass"`)

User names, accounts and permissions are pack variables; **passwords never
are**: each user's password is the item `password` of the secret
`<users_secret_prefix>/<name>` (default `nats/users/<name>`) in the namespace
of the job, read by the servers with `nomadSecret` into their configuration
(`secrets/nats.conf`, mode 0600, the job's `secret_access` grants one path per
user). It may be plain or a bcrypt hash (`nats server passwd`; NATS recognizes
the `$2a$`/`$2b$` prefix), so that the servers need not know the plain
password the clients use.

```hcl
auth_mode = "userpass"
users = [
  # its own account: own subjects, own JetStream streams and KV buckets
  { name = "openobserve", account = "OPENOBSERVE" },
  # the shared account (users_default_account, "APP"), with permissions
  {
    name            = "orders"
    publish_allow   = ["orders.>", "$JS.API.>"]
    subscribe_allow = ["orders.>", "nomad.>", "_INBOX.>"]
  },
  # the system account (system_account, "SYS"): nats server report, raft peer-remove
  { name = "ops", account = "SYS" },
]
```

```shell
norca secret put nats/users/openobserve password=-
norca secret put nats/users/orders password=-
norca secret put nats/users/ops password='$2a$11$...'   # a bcrypt hash: the servers never see the password
norca pack run nats --registry=norca -f nats.hcl
```

(`-namespace <ns>` with the namespace of the job; `norca pack run` prints the
commands for the configured users.) [`examples/nats/userpass.hcl`](../../examples/nats/userpass.hcl)
is a complete variable file.

- **Accounts.** Every user is in an account (`account`, default
  `users_default_account` = `APP`). Accounts are isolated: subjects,
  JetStream streams and KV buckets of one account are invisible to the others
  (the pack defines no exports or imports; use `auth_mode = "config"` for
  that). Every account except the system account has JetStream when
  `jetstream_enabled`. All users are in named accounts: NATS gives the global
  account no JetStream once other accounts exist.
- **Permissions** (`publish_allow`, `publish_deny`, `subscribe_allow`,
  `subscribe_deny`, `allow_responses`) restrict a user inside its account; no
  lists, no restriction. A client using JetStream needs `$JS.API.>` (or the
  API subjects it uses) to publish and `_INBOX.>` to subscribe.
- **The system account.** Users whose account is `system_account` (`SYS`)
  are in the servers' system account: the `nats` CLI's server commands. Without
  such a user the servers keep their internal system account.
- **The bridge** (`bridge_enabled`): norca-natsbridge has no password option,
  so its user is an NKey user in `users_default_account`, with the public key
  `bridge_nkey` and the seed in the item `seed` of the secret
  `<users_secret_prefix>/<bridge_job_name>`, which only the bridge job reads.
  It may publish `<bridge_subject_prefix>.>`, look up and create streams
  (`$JS.API.STREAM.INFO.*`, `$JS.API.STREAM.CREATE.*`) and receive replies on
  `_INBOX.>`; with `bridge_sync_pushes` also `<prefix>.packs.pushed` and
  `<prefix>.packs.pushed.>`, with `bridge_sync_regions` `<prefix>.*.CustomObject`.
  Consumers of the events, and the CI that publishes push notices, need a user
  in the same account.

  ```shell
  nk -gen user > bridge.seed && nk -inkey bridge.seed -pubout   # the public key: bridge_nkey
  norca secret put nats/users/natsbridge seed=@bridge.seed
  ```

- **The metrics exporter** needs no user: it reads the HTTP monitoring port,
  which NATS serves without authentication (keep it on the private network),
  and sees all accounts there.
- **TLS** works the same with this mode (`tls_enabled`, the certificates from
  the Variable). Without TLS the passwords cross the network in clear text:
  keep the client port on the VPN.
- **A supercluster** needs the same users and accounts in every region (each
  region renders its own configuration; interest crosses the gateways per
  account name), and the secrets in every region.

**Changes and reloads.** The servers wait for every secret at their start
(the template blocks until it exists, up to five minutes, then the task fails
and is restarted). A missing `password` item fails the template instead of
rendering an empty password. A **new version of a secret** is picked up by
the client agent's watch: the configuration renders again and the servers
reload (`SIGHUP`, no restart): from then on the new password applies,
connections authenticated with the old one are closed (NATS checks every
client again on a reload) and must reconnect with the new one. NATS has one
password per user, so a rotation is:

1. put the new password (or its hash) into `<users_secret_prefix>/<name>`;
   the servers reload within seconds;
2. give the client the new password (e.g. its own secret; a client that reads
   it with a `secret` block restarts with it).

Between the two steps the client can't connect. Without that gap: add a second
user in the same account, move the client to it, remove the first. Changes of
`users` (names, accounts, permissions) change the job and replace the servers
one at a time (rolling update, lame duck), like every other variable.

**Switching an existing installation** from `none`/`token`/`nkey` to
`userpass` moves the clients from the global account into named accounts: the
JetStream streams of the global account (e.g. the bridge's
`NORCA_EVENTS_<region>`) stay on disk but are not visible in the new accounts.
Recreate them (the bridge creates its stream again) or migrate them before the
switch.

## Multi-region walkthrough

Three regions, one per cloud (`aws`, `gcp`, `hetzner`), federated, with the
VPN between the nodes. The NATS ports are bound to the VPN interface through
a client `host_network`, e.g. on every client:

```hcl
client {
  host_network "wg" {
    interface = "wg0"
  }
}
```

1. **Secrets per region** (each region has its own Variables; a shared CA
   lets the gateways verify each other):

   ```
   norca var put -region aws nomad/jobs/nats tls_ca=@ca.pem tls_cert=@aws.pem tls_key=@aws-key.pem client_token=<token>
   norca var put -region gcp nomad/jobs/nats tls_ca=@ca.pem tls_cert=@gcp.pem tls_key=@gcp-key.pem client_token=<token>
   norca var put -region hetzner nomad/jobs/nats ...
   ```

2. **A variable file per region**, with the gateway addresses of the other
   regions over the VPN (the static gateway port, default 7222; one URL per
   remote cluster is enough, the others are discovered):

   ```hcl
   # aws.hcl
   region          = "aws"
   host_network    = "wg"
   gateway_enabled = true
   tls_enabled     = true
   auth_mode       = "token"
   separate_scope  = "$${node.datacenter}"
   remote_gateways = [
     { name = "gcp",     urls = ["nats://10.20.0.11:7222", "nats://10.20.0.12:7222"] },
     { name = "hetzner", urls = ["nats://10.30.0.11:7222", "nats://10.30.0.12:7222"] },
   ]
   bridge_enabled  = true
   ```

   `gcp.hcl` and `hetzner.hcl` are the same with their own `region` and the
   other two regions in `remote_gateways`. The gateway name of a region is its
   `cluster_name`, by default the region name. The TLS certificates must be
   valid for the gateway URLs (here the VPN addresses).

3. **Deploy the pack in every region:**

   ```
   norca pack run nats --registry=norca --var-file aws.hcl
   norca pack run nats --registry=norca --var-file gcp.hcl
   norca pack run nats --registry=norca --var-file hetzner.hcl
   ```

   (or `norca pack run ./packs/nats ...` from a checkout). The addresses of
   the gateways of a region are listed by
   `norca service info -region aws nats-gateway`.

4. **Check** on any server's monitoring port (`norca service info nats-monitor`):
   `/routez` (routes to the other servers of the region), `/gatewayz`
   (outbound and inbound gateways to every other region), `/jsz` (the
   JetStream meta group spans the whole supercluster: `cluster_size` is the
   number of servers in all regions, one meta leader), `/healthz`.

5. **The bridge** of every region needs its ACL policy (the pack cannot
   create ACL policies; `norca pack run` prints the policy text):

   ```
   norca acl policy apply -region aws -namespace default -job natsbridge \
     natsbridge natsbridge-policy.hcl
   norca var put -region aws nomad/jobs/natsbridge nats_token=<token> nats_ca=@ca.pem
   ```

   The policy is
   [`nomad/natsbridge/examples/natsbridge-policy.hcl`](https://github.com/bacanoo-io/norca/blob/main/nomad/natsbridge/examples/natsbridge-policy.hcl)
   of the Norca repository (read-job
   in all namespaces, node read, list/read/write on
   `nomad/jobs/natsbridge/*` for the checkpoint and the leader election
   lease). The bridge reads its own NATS credentials from
   `nomad/jobs/<bridge_job_name>`: `nats_token`, `nats_creds` (JWT
   credentials file), `nats_nkey_seed`, `nats_ca`, `nats_cert`/`nats_key`;
   all are optional.

### JetStream in the supercluster

- A supercluster has **one JetStream meta group** spanning all regions
  (creating and deleting streams needs a majority of all servers, e.g. 5 of
  9); the data of a stream lives only in the cluster it is placed in and
  needs only the majority of its own replicas. Losing a cloud therefore stops
  neither the streams of the other regions nor, with 3 regions of 3 servers,
  the meta group.
- Stream names are global in the supercluster: keep the region in the name.
  The bridge default is `NORCA_EVENTS_<region>` for the subjects
  `nomad.<region>.>`; it creates the stream in its own region if missing,
  with a single replica. For durability create it beforehand with three
  replicas, placed in the region:

  ```
  nats stream add NORCA_EVENTS_aws --subjects 'nomad.aws.>' --replicas 3 \
    --cluster aws --storage file --retention limits --max-age 7d \
    --dupe-window 10m --discard old
  ```

  The duplicate window must cover the bridge's redeliveries after a restart
  (it deduplicates with `Nats-Msg-Id`; the bridge uses 10m for the streams it
  creates).
- A central history or audit service can read all regions with a **mirror or
  sources** stream in its own region (`--source NORCA_EVENTS_aws
  --source NORCA_EVENTS_gcp ...`) or a consumer per region stream; plain
  subscribers use `nomad.*.>` (all regions) or `nomad.<region>.>`.
- Keep `jetstream_domain` empty in the supercluster. Edge sites can attach as
  leaf nodes (`leafnodes_enabled`, port 7422) with their own domain.

## Variables

See `variables.hcl` for all of them; the most important:

| Variable | Default | |
|---|---|---|
| `count` | `3` | servers in the region (odd, ≥ 3 for JetStream) |
| `driver` | `docker` | `docker`, `raw_exec`, `exec` |
| `cluster_name` | region | cluster and gateway name |
| `gateway_enabled`, `remote_gateways` | `false`, `[]` | supercluster |
| `host_network` | `""` | bind the ports to e.g. the VPN interface |
| `client_port`, `cluster_port`, `gateway_port`, `monitor_port`, `leafnode_port` | 4222, 6222, 7222, 8222, 7422 | 0 = dynamic |
| `storage` | `ephemeral_disk` | `ephemeral_disk`, `host_volume`, `path` |
| `tls_enabled`, `auth_mode` | `false`, `none` | secrets from `secrets_variable`; `auth_mode`: `none`, `token`, `nkey`, `config`, `userpass` |
| `users`, `users_secret_prefix`, `users_default_account`, `system_account`, `bridge_nkey` | `[]`, `nats/users`, `APP`, `SYS`, `""` | `auth_mode = "userpass"`: users, accounts, permissions; passwords from the secret store |
| `disruption_max_unavailable` | `"1"` | empty removes the block |
| `bridge_enabled` | `false` | deploys the bridge |
| `bridge_sync_pushes`, `bridge_sync_regions` | `false`, `false` | the bridge syncs the cluster pack registries on push notices / on the registry events of other regions |
| `metrics_enabled`, `metrics_image`, `metrics_port` | `false`, `natsio/prometheus-nats-exporter:0.20.2`, `0` | the Prometheus exporter (0 = dynamic port) |

## Metrics

nats-server has no Prometheus endpoint, only the JSON monitoring endpoints
(`/varz`, `/connz`, `/jsz`, ...). With `metrics_enabled = true` every server
allocation also runs the official
[NATS Prometheus exporter](https://github.com/nats-io/prometheus-nats-exporter)
(Apache-2.0; image `docker.io/natsio/prometheus-nats-exporter:0.20.2`, release
of 2026-08-19, index digest
`sha256:c623b608e148e31e1c1c878673a197f1828e58ce90de4f01d22f1baa84c8fee9`)
as a poststart sidecar task `metrics`. It polls the monitoring port of its own
server (`/varz`, `/connz`, `/routez`, `/subsz`, `/healthz`, `/jsz` with
JetStream, `/gatewayz` with gateways, `/leafz` with leaf nodes) and serves
`/metrics` on the port `metrics` (dynamic unless `metrics_port`), registered
as the service `<job>-metrics` (tag `metrics`, no checks: the exporter never
holds up the deployments of the servers). The
[otel-collector pack](../otel-collector/README.md) finds the instances through
the native catalog and scrapes on each node the exporters of that node.

The exporter reaches the monitoring port over plain HTTP (it has no TLS client
options); the monitoring port of this pack is always plain HTTP. Metrics are
off by default so that existing installations keep their jobs unchanged.

## Development and testing

On a development agent with `raw_exec` enabled, without Docker:

```
go install github.com/nats-io/nats-server/v2@v2.15.0
norca pack run ./packs/nats --var driver=raw_exec --var binary=$(go env GOPATH)/bin/nats-server \
  --var distinct_hosts=false --var client_port=0 --var cluster_port=0 --var monitor_port=0
```

Dynamic ports let the three servers share one node. `norca pack render`
shows the jobs without submitting them.

## Limitations

- The pack cannot create ACL policies, Variables or secrets; it prints the
  commands.
- `auth_mode = "userpass"`: one password per user (rotation has a short gap,
  see above), no exports/imports between accounts, no per-account JetStream
  limits, leaf node authorization not configured. Checked with
  `nats-server -t` and a local single server (passwords with quotes,
  backslashes and `{{ }}`, bcrypt, account isolation, the bridge's
  permissions, the reload), not on a cluster yet.
- `raw_exec` binds to the node address but has no isolation, and cannot mount
  host volumes; `SIGHUP`/`SIGUSR2` need a Unix node.
- The routes and gateways have no password authentication; protect them with
  mutual TLS and the VPN.
- Removing a server for good (scaling down, a lost node with `host_volume` or
  `path` storage) leaves an offline JetStream peer to remove manually.
- A change of the server list restarts the bridge (it resumes from its
  checkpoint; JetStream drops the duplicates).
