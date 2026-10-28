<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# forgejo

[Forgejo](https://forgejo.org) as the internal **git server** and **container
(OCI) registry** of a Norca cluster: one Forgejo instance with SQLite and the
git repositories on a client host volume; container images, LFS objects,
attachments and avatars in the RustFS of the [rustfs pack](../rustfs/README.md)
(any S3 store works); its keys, the admin password, the S3 credentials and the
TLS certificate from Norca's built-in secret store; health checks with roles;
optional HTTPS, SSH, initial admin and periodic dumps.

The nodes then pull internal images from Forgejo (`forgejo.internal/<owner>/<image>:<tag>`)
with one Docker auth file per client, without auth blocks in the jobs; images
from Docker Hub keep coming from Docker Hub. See
[Forgejo as the image registry of the nodes](#forgejo-as-the-image-registry-of-the-nodes).

## License: Forgejo is GPL, referenced, never shipped

> **Forgejo is licensed under the GNU General Public License v3.0 or later**
> (since v9; [LICENSE](https://codeberg.org/forgejo/forgejo/src/branch/forgejo/LICENSE)).
> Norca does not distribute, include or modify Forgejo, and ships no Forgejo
> binary or image. This pack only *references* the official image by name,
> tag and optionally digest; the nodes pull it from Codeberg (or your mirror of
> the unmodified image). Running it, also in production, needs no permission;
> the GPL's obligations apply to those who distribute Forgejo, modified or
> not (e.g. a mirror you give to others): the source is at
> [codeberg.org/forgejo/forgejo](https://codeberg.org/forgejo/forgejo).

The pack itself (these templates) is MPL 2.0 like the rest of this registry.

## Image

| | |
| --- | --- |
| Default image | `codeberg.org/forgejo/forgejo:15.0.10-rootless` (official mirror: `data.forgejo.org/forgejo/forgejo`) |
| Release | [v15.0.10](https://codeberg.org/forgejo/forgejo/releases/tag/v15.0.10), 2026-10-12, of the **v15 LTS** line |
| Index digest | `sha256:6ffebd9ab9ee9f6677e3523fa60debd9de630ff2a226fa681d6cc0c7ba541d77` (linux/amd64, arm64, arm) |
| Container user | `1000:1000` (`git`), data in `/var/lib/gitea`, HTTP on 3000, SSH on 2222 |

Why LTS: a cluster's git server and image registry should change rarely. An
LTS line gets security and critical fixes for one year and three months
([release life cycle](https://forgejo.org/docs/v15.0/admin/upgrade/)), while a
non-LTS major is replaced by the next one after about three months. v17.0.0 (2026-10-15) and
the 2026-10-26 patch releases (15.0.11, 16.0.7, 17.0.1) are less than two weeks
old, so 15.0.10 is the newest LTS release that can be pinned now. Move to
15.0.11 after 2026-11-09 (read its release notes; patch releases often fix
security problems). The *rootless* variant runs as an unprivileged user and has
the built-in SSH server, so no root process and no OpenSSH run in the
container.

Pin the digest with `image_digest`, and mirror the image into your internal
registry for air-gapped clusters (`image`).

## What lives where

| Data | Where |
| --- | --- |
| `app.ini` (written from the `FORGEJO__*` variables at every start), the SQLite database, the **git repositories**, search indexes, sessions, logs | the host volume (`/var/lib/gitea`) |
| container images and other packages, LFS objects, attachments, avatars, repository archives, Actions logs and artifacts | the S3 bucket `storage_bucket` (one directory per kind: `packages/`, `lfs/`, `attachments/`, ...) |
| `SECRET_KEY`, `INTERNAL_TOKEN`, the JWT secrets, the TLS certificate | the secret store; rendered into files in the task's `secrets/` and named in `app.ini` as `SECRET_KEY_URI = file:/secrets/secret_key` etc., never copied into `app.ini` |
| the S3 credentials | the secret store; passed as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, which Forgejo's S3 client uses when `app.ini` has no keys |

**Git repositories can't live in S3**: git needs a POSIX file system (locks,
renames, hooks), so the repositories and SQLite stay on the host volume. That
makes Forgejo **one instance on one node**: give exactly one client the host
volume `forgejo` (the volume ties the job to it), and back up the volume
([dumps](#backups)). A second instance would need PostgreSQL and a shared
file system, which this pack doesn't cover.

The storage settings are those of Forgejo 15
([storage](https://forgejo.org/docs/v15.0/admin/setup/storage/)):
`[storage] STORAGE_TYPE = minio`, `MINIO_ENDPOINT`, `MINIO_BUCKET`,
`MINIO_BUCKET_LOOKUP = path` (path-style requests, as RustFS serves them),
`MINIO_LOCATION`, `MINIO_USE_SSL`. The endpoint is the first instance of the
catalog service `storage_service` (`rustfs`, in the namespace of the job),
looked up by a template; `storage_endpoint` names a fixed `host:port` instead.
A change of the endpoint restarts Forgejo.

## Prerequisites

1. **The S3 store**: the rustfs pack (or another S3 store), with the bucket of
   Forgejo, e.g. `buckets = ["norca-backup", "forgejo", "forgejo-dump"]` in
   its variables. Forgejo also creates `storage_bucket` at its start if its
   key may create buckets.
2. **An S3 user for Forgejo** (recommended over the root key): RustFS has IAM
   users with their own access keys and policies (its console, or the
   MinIO-compatible admin API). Create a user `forgejo` with read and write
   access to the buckets `forgejo` and `forgejo-dump` only.
3. **The host volume** on the one Forgejo node, owned by the container user:

   ```hcl
   client {
     host_volume "forgejo" {
       path      = "/srv/forgejo"
       read_only = false
     }
   }
   ```

   ```shell
   sudo install -d -o 1000 -g 1000 -m 750 /srv/forgejo
   ```

4. **A DNS name** (`domain`) that the users and the Docker daemons of all
   nodes resolve to the Forgejo node, or to the proxy in front of it: a record
   in your DNS, or the name of Norca's built-in DNS
   (`forgejo.service.<namespace>.nomad`) when the resolver of the hosts
   forwards `.nomad` to it.
5. **HTTPS for the registry** (Docker refuses plain HTTP to a registry on
   another host): a certificate for `domain` whose CA the Docker daemons trust,
   see [TLS](#tls).

## Secrets

All secrets are in the namespace of the job. Values on the command line end up
in the shell history: use files or standard input, and delete the files
afterwards.

```shell
# The keys of Forgejo. The JWT secrets must be base64url of 32 bytes: generate
# them with Forgejo itself (an invalid one is replaced in app.ini, which then
# conflicts with the *_URI setting).
img=codeberg.org/forgejo/forgejo:15.0.10-rootless
umask 077
for s in SECRET_KEY INTERNAL_TOKEN JWT_SECRET LFS_JWT_SECRET; do
  docker run --rm --entrypoint forgejo "$img" generate secret "$s" > "$(echo "$s" | tr A-Z a-z)"
done
norca secret put forgejo/keys secret_key=@secret_key internal_token=@internal_token \
  jwt_secret=@jwt_secret lfs_jwt_secret=@lfs_jwt_secret
rm -f secret_key internal_token jwt_secret lfs_jwt_secret

norca secret put forgejo/admin password=-                            # the initial admin
norca secret put forgejo/storage access_key=forgejo secret_key=-     # the S3 user of Forgejo
norca secret put forgejo/tls cert=@forgejo.pem key=@forgejo-key.pem  # with https_enabled
```

`SECRET_KEY` encrypts data in the database (e.g. 2FA secrets): keep the secret
`forgejo/keys`; without it a restored database is of little use. The secret
store is part of Norca's backups.

## Install

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=<tag>
norca pack run forgejo --registry=norca --name=forgejo -f forgejo.hcl
norca service info -verbose forgejo
norca alloc logs -task create-admin <alloc ID>     # "admin forgejo-admin created"
```

From a checkout of this registry: `norca pack run ./packs/forgejo -f examples/forgejo/registry-https.hcl`.
Example variable files are in [`examples/forgejo`](../../examples/forgejo).

The poststart task `create-admin` waits for `/api/healthz`, then runs
`forgejo admin user create --admin` with the password of `forgejo/admin`. A
user of that name that exists already is left alone, so a restart or upgrade
doesn't touch it; change the password in Forgejo afterwards if you like. Set
`admin_enabled = false` once the admin exists, or keep it for new installs.

## Forgejo as the image registry of the nodes

Decision of 2026-10-27, "Forgejo + auth": Forgejo is the internal image
registry, and the Docker driver of every client authenticates to it with one
auth file, so jobs reference `forgejo.internal/<owner>/<image>:<tag>` without
`auth` blocks. Images without an entry in the file (Docker Hub and other
registries) are pulled as before. Nothing changes in Norca itself.

How the Docker driver uses the file (verified in the Nomad 1.6.5 driver,
`drivers/docker/config.go` and `utils.go`): the plugin option
`auth { config = "<file>" }` (or `helper = "<name>"`) names a Docker
`config.json`; at every pull the driver looks up the registry of the image in
it (`auths`, then `credHelpers` and `credsStore`). A task's own `auth` block
wins over the file, the file over the helper. The file is read at each pull,
so a new token needs no restart; the plugin option itself is read when the
agent starts.

1. **An owner for the images**: an organization in Forgejo, e.g. `platform`.
   Container images are packages of their owner; private ones are readable by
   its members (team permission *Packages: Read*).
2. **A pull-only user and token**: a user `registry-pull` without admin rights,
   member of a team of `platform` with *Packages: Read* only, and an access
   token with the scope `read:package`:

   ```shell
   norca alloc exec -task forgejo <alloc ID> forgejo admin user create \
     --username registry-pull --email registry-pull@forgejo.internal --random-password \
     --must-change-password=false --access-token --access-token-name nodes \
     --access-token-scopes read:package
   # prints the token once; then add the user to the team in the web UI
   ```

3. **The token in the secret store** (a namespace your operators can read):

   ```shell
   norca secret put registry/forgejo-pull username=registry-pull token=-
   ```

4. **The auth file on every client**, readable by root only. The key is the
   registry host exactly as in the image names: `forgejo.internal`, or
   `forgejo.internal:3000` with a port.

   ```shell
   registry=forgejo.internal
   auth=$(printf 'registry-pull:%s' "$(norca secret get -item token registry/forgejo-pull)" | base64 -w0)
   sudo install -d -m 700 /etc/norca
   printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$registry" "$auth" | sudo tee /etc/norca/docker-auth.json >/dev/null
   sudo chmod 600 /etc/norca/docker-auth.json
   ```

   Distribute it with your configuration management like the agent
   configuration. To rotate the token, create a new one, write the file on
   every client, then delete the old token.
5. **The Docker plugin of every client** reads the file:

   ```hcl
   plugin "docker" {
     config {
       auth {
         config = "/etc/norca/docker-auth.json"
       }
     }
   }
   ```

   Restart the agent (`sudo systemctl restart norca`; plugin options are not
   reloaded by SIGHUP). Running allocations keep running.
6. **Push and use images**:

   ```shell
   docker login forgejo.internal                # a user with write access to the packages of platform
   docker tag app:1.0 forgejo.internal/platform/app:1.0
   docker push forgejo.internal/platform/app:1.0
   ```

   ```hcl
   config {
     image = "forgejo.internal/platform/app:1.0"
   }
   ```

A credential helper (`auth { helper = "forgejo" }` runs
`docker-credential-forgejo get`) fits when the credentials come from a vault at
pull time; with one long-lived pull token the file is simpler.

### TLS

Docker talks HTTPS to every registry except `localhost`. Three ways:

- **Forgejo serves HTTPS** (`https_enabled = true`, e.g. `http_port = 443`):
  the certificate and key from `tls_secret_path` (items `cert`, with the
  chain, and `key`). The Docker daemons must trust its CA: put it into
  `/etc/docker/certs.d/<registry host>/ca.crt` on every node (or the system
  trust store). Norca's HTTP checks verify certificates against the instance
  address, which the certificate doesn't name, so with HTTPS the checks are TCP
  checks (the readiness of `/api/healthz` is then not checked).
- **A TLS-terminating proxy** in front of Forgejo (a load balancer, Traefik,
  Caddy, ...): Forgejo serves HTTP on `http_port`, `root_url` is the URL of
  the proxy (`https://forgejo.internal/`), and the registry name is the host
  of the proxy. Keep the HTTP port of Forgejo reachable from the proxy only.
- **Lab only: `insecure-registries`** in `/etc/docker/daemon.json` of every node
  (`{"insecure-registries": ["forgejo.internal:3000"]}`, then restart Docker).
  The images, the token and the users' passwords then cross the network in
  clear text and can be tampered with. Never in production.

## Backups

Norca's backups cover the **cluster state only** (Raft, keyring, secret store),
not the data of applications. Forgejo needs its own:

- `dump_enabled = true` adds the periodic batch job `<job>-dump`
  (`dump_cron`, UTC). It runs `forgejo dump` on the Forgejo node (the host
  volume read-only): the database as SQL, the git repositories and the custom
  files, **without** the objects already in S3 (packages, LFS, attachments,
  archives), and uploads the `.tar.gz` to `dump_bucket`/`dump_prefix` with an
  S3 PUT signed by curl. The dumps are not encrypted: keep the bucket private
  and expire old dumps with a lifecycle rule of the bucket.
- The **objects in S3** need a backup of the bucket `storage_bucket` itself
  (replication of RustFS to another site, or a periodic copy).
- **Restore** (outline; Forgejo's [upgrade guide](https://forgejo.org/docs/v15.0/admin/upgrade/#backup)
  covers the backup):
  stop the job, unpack the dump into the host volume (repositories to
  `git/repositories`, `custom/`), rebuild the SQLite database from
  `forgejo-db.sql` (`sqlite3 data/gitea.db < forgejo-db.sql`, as uid 1000),
  keep the same `forgejo/keys`, run the job, then
  `forgejo admin regenerate hooks` in the task.

Take a dump before every upgrade, and upgrade within the LTS line (15.0.x)
unless the release notes say otherwise.

## Variables

| Variable | Default | |
| --- | --- | --- |
| `job_name`, `namespace`, `region` | `""` | empty: `forgejo`, those of the release |
| `datacenters`, `node_pool`, `constraints` | `["*"]`, `""`, `[]` | placement (the host volume decides the node) |
| `image`, `image_digest` | `codeberg.org/forgejo/forgejo:15.0.10-rootless`, `""` | |
| `uid`, `gid` | `1000`, `1000` | container user, owner of the volume and of the secret files |
| `resources` | `{cpu = 1000, memory = 1024}` | |
| `host_volume` | `forgejo` | mounted at `/var/lib/gitea` |
| `domain` | `forgejo.internal` | `DOMAIN`, `SSH_DOMAIN`, the registry host |
| `http_port` | `3000` | static port on the node (3000 in the container) |
| `root_url` | `""` | empty: `<scheme>://<domain>[:<http_port>]/` |
| `host_network` | `""` | client host network of the ports |
| `app_name`, `disable_registration`, `require_signin_view` | `Forgejo`, `true`, `false` | |
| `extra_env` | `{}` | more `FORGEJO__<section>__<KEY>` settings (no secrets; the schema rejects keys that look like secrets) |
| `https_enabled`, `tls_secret_path` | `false`, `forgejo/tls` | Forgejo's own HTTPS |
| `ssh_enabled`, `ssh_port` | `true`, `2222` | git over SSH (built-in server) |
| `keys_secret_path` | `forgejo/keys` | `secret_key`, `internal_token`, `jwt_secret`, `lfs_jwt_secret` |
| `admin_enabled`, `admin_username`, `admin_email`, `admin_secret_path` | `true`, `forgejo-admin`, `forgejo-admin@forgejo.internal`, `forgejo/admin` | the initial admin |
| `storage_enabled` | `true` | objects in S3; `false` keeps everything on the volume |
| `storage_service`, `storage_endpoint` | `rustfs`, `""` | catalog lookup, or a fixed `host:port` |
| `storage_use_ssl`, `storage_bucket`, `storage_region`, `storage_secret_path` | `false`, `forgejo`, `us-east-1`, `forgejo/storage` | |
| `metrics_enabled`, `metrics_token_secret_path` | `false`, `forgejo/metrics` | `/metrics` for the otel-collector pack, see [Metrics](#metrics) |
| `dump_enabled`, `dump_cron`, `dump_bucket`, `dump_prefix`, `dump_resources` | `false`, `0 3 * * *`, `forgejo-dump`, `forgejo/`, `{cpu = 500, memory = 512}` | the dump job |
| `startup_timeout`, `healthy_deadline` | `5m`, `10m` | |

The values are checked against the `validation` blocks and rules of
[`variables.hcl`](variables.hcl) before rendering; the servers check the
`validation` blocks again.

## Metrics

With `metrics_enabled = true` Forgejo serves Prometheus metrics on `/metrics`
(`[metrics] ENABLED`, verified in `modules/setting/metrics.go` and
`routers/web/metrics.go` of v15.0.10), and the HTTP service gets the tag
`metrics`, which the [otel-collector pack](../otel-collector/README.md) looks
for. The endpoint requires `Authorization: Bearer <token>` with the item
`token` of `metrics_token_secret_path` (`forgejo/metrics`); the collector reads
the same secret. Forgejo has no `TOKEN_URI` for this setting: the token is
rendered into `secrets/metrics_token` and passed with
`FORGEJO__metrics__TOKEN__FILE`, which the image writes into `app.ini` at
every start (on the host volume, readable only by the container user). An
empty `metrics_token_secret_path` serves `/metrics` without a token.

```shell
openssl rand -hex 32 | norca secret put forgejo/metrics token=-
```

Metrics are off by default so that existing installations keep their jobs
unchanged.

## Health checks

| Role | HTTP (default) | HTTPS |
| --- | --- | --- |
| startup | TCP on the HTTP port, every 5 s, at most `startup_timeout` | TCP |
| readiness | `GET /api/healthz` every 10 s (database and cache) | TCP |
| liveness | `GET /api/healthz` every 30 s | TCP |

The SSH service `<job>-ssh` has a TCP readiness check.

## Later

Planned, not built:

- **A pull-through cache for Docker Hub**: the CNCF Distribution `registry`
  (Apache-2.0) in proxy mode (`proxy.remoteurl = https://registry-1.docker.io`)
  as a job, with its storage in RustFS (the `s3` storage driver), wired in
  through `registry-mirrors` in `/etc/docker/daemon.json` of every node. Docker
  uses mirrors for Docker Hub only, so it complements Forgejo, it doesn't
  replace it.
- **A Norca server option that rewrites unqualified docker images** (`redis:7`)
  to the internal registry at registration, so jobs don't name it.

## Limitations

- One instance (SQLite, repositories on one node's host volume); no
  failover beyond rescheduling to a node with the same volume.
- With `https_enabled` the checks are TCP checks.
- The S3 endpoint is the first catalog instance of `storage_service` in the
  namespace of the job when the task starts; other namespaces or regions need
  `storage_endpoint`.
- Mail, OAuth2 providers and other settings with secrets can't go through
  `extra_env`; configure them in the web UI or extend the pack.
- The pack has been rendered and validated by the checks of this registry,
  but not run against a live cluster yet (the poststart admin task and the
  dump job in particular).
