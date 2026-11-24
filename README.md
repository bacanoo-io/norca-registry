<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# Norca pack registry

The public pack registry of [Norca](https://github.com/bacanoo-io/norca): the
operations packs that install the infrastructure around a Norca cluster (NATS,
the cross-region mTLS gateway, the backup store, the git server and image
registry, PostgreSQL, observability with OpenObserve and the OpenTelemetry
Collector, optional Consul) and the
reference operator pack. `norca pack` uses it like any git pack registry
(Nomad Pack format, with Norca's extended package format: object kinds, ACL and
admission policies next to jobs, a JSON Schema for the variables).

## Modules of Rigger (branch `rigger`)

On the branch `rigger` of this clone (`norca-rigger-registry`), the packs are
converted to modules of [Rigger](https://github.com/bacanoo-io/norca-rigger), the
package manager that replaces `norca pack` (design of Rigger, sections 7.4 and
13). The modules live in `modules/` next to `packs/`, so both are checked in
one tree until the packs go; the branch is merged into norca-registry then.
A stack names this repository as a registry and installs a module by name:

```hcl
rigger {
  name = "platform"

  registry "norca" {
    source = "github.com/bacanoo-io/norca-registry"
  }
}

module "bus" {
  source  = "norca/nats"
  version = "~> 2.0"
}
```

Each module has its own version and is released by a tag
`<module>/v<version>` (`nats/v2.0.0`), never moved. A version is published
with the signing key of the namespace `norca` of the global registry
(`norca-global-registry`): `rigger module publish modules/<module> -key
norca.key` signs the module, commits the signature and tags it; once the tag
is pushed, the global registry lists it as `norca/<module>`. The tags made
before the key are not signed: a module enters the global registry with its
next version. The scripts of the registry, with the `rigger` program on the
PATH:

- `scripts/check-modules.sh`: `rigger fmt -check`, `rigger module validate` (the
  defaults and the example values rendered through Norca's job decoder) and
  `rigger module test` of every module.
- `scripts/compare-packs.sh <pack>...`: the acceptance of a conversion (rigger
  design 14). For the defaults and every example, the module renders the
  jobs, ACL policies, kinds and admission policies of the pack, compared as
  parsed resources (the pack's resource files rendered by rigger in a module of
  their own, so both pass the same decoders). An example of the module that
  the pack has not is given to both. The module is rendered in the namespace
  the example of the pack sets, or else in the default of the pack's
  `namespace` variable (`norca-system` for the operator packs). An example
  that sets variables the pack has not is named in the script
  (`module_only`, each with its reason): it is rendered, printed as `not
  compared`, and nothing else is left out.
- `scripts/check-modules-server.sh`: every job the modules render, for the
  defaults and every example, passes the validation of a Norca server
  (`PUT /v1/validate/job`; `CREATE_NODE_POOLS=1` on a throwaway dev agent).

Every pack of the registry is converted (`rigger convert pack`, then the
templates written as HCL); all 89 cases of `compare-packs.sh` match, 2
examples are of a module alone (not compared), and all 110 rendered jobs
pass the server's validation.

| Module | Version | From |
| --- | --- | --- |
| [consul](modules/consul/README.md) | 0.2.0 | the pack consul 0.2.0, in full |
| [forgejo](modules/forgejo/README.md) | 0.2.0 | the pack forgejo 0.2.0, in full |
| [loadbalancer-operator](modules/loadbalancer-operator/README.md) | 0.5.0 | the pack loadbalancer-operator 0.4.0, in full |
| [mtls-gateway](modules/mtls-gateway/README.md) | 0.2.1 | the pack mtls-gateway 0.2.1, in full |
| [nats](modules/nats/README.md) | 2.0.0 | the pack nats 0.7.0, in full |
| [nats-demo](modules/nats-demo/README.md) | 1.0.0 | a demonstration of the language: the pack nats 0.7.0 in a smaller shape (was nats 1.0.0) |
| [nodescaler-operator](modules/nodescaler-operator/README.md) | 0.11.0 | the pack nodescaler-operator 0.11.0, in full |
| [norca-acme](modules/norca-acme/README.md) | 0.3.0 | the pack norca-acme 0.2.0, in full, and several instances with leader election |
| [norca-dns](modules/norca-dns/README.md) | 0.3.0 | the pack norca-dns 0.2.0, in full, and several instances with leader election |
| [norca-provider](modules/norca-provider/README.md) | 0.5.0 | the pack norca-provider 0.5.0, in full |
| [openobserve](modules/openobserve/README.md) | 0.2.1 | the pack openobserve 0.2.0, in full |
| [otel-collector](modules/otel-collector/README.md) | 0.1.2 | the pack otel-collector 0.1.2, in full |
| [postgres](modules/postgres/README.md) | 0.4.0 | the pack postgres 0.1.0, in full |
| [postgres-demo](modules/postgres-demo/README.md) | 0.3.1 | a demonstration of the language from the pack postgres (was postgres 0.3.0) |
| [redis](modules/redis/README.md) | 0.3.0 | the built-in pack redis 0.2.1 of norca, its faults kept |
| [rustfs](modules/rustfs/README.md) | 0.2.0 | the pack rustfs 0.2.0, in full |
| [seaweedfs](modules/seaweedfs/README.md) | 0.1.0 | the pack seaweedfs 0.1.0, in full |
| [seaweedfs-csi](modules/seaweedfs-csi/README.md) | 0.1.0 | the pack seaweedfs-csi 0.1.0, in full |
| [traefik](modules/traefik/README.md) | 0.3.0 | the pack traefik 0.3.0, in full |
| lib/placement | 1.1.0 | a library the others call; not installed on its own |

The operator modules (loadbalancer-operator, nodescaler-operator, norca-acme,
norca-dns, norca-provider) follow what [Operator packs](#operator-packs)
says of their packs. A module has no `namespace` variable: its jobs, the ACL
policies bound to them and, by default, their token Variables and secrets
are in the namespace of the release, so install them with `-namespace
norca-system`. The modules expect the namespace and don't create it: create
it once with `norca namespace apply -description "Norca operators"
norca-system`. Their jobs carry the same constraint on
`${attr.driver.raw_exec}` and the same default driver `exec`, and
`allow_raw_exec_nodes` leaves the constraint out; `driver = "raw_exec"`
without it is refused by the rule `raw_exec` of the module (the `fail` of
the pack), which the tests of each of the five modules check.

## Packs

| Pack | Version | |
| --- | --- | --- |
| [consul](packs/consul/README.md) | 0.2.0 | Installs and manages the official HashiCorp Consul release (BSL 1.1, referenced, never shipped; accepted by the user at install): servers on host volumes over datacenters, client agents, gossip/TLS/ACL bootstrap from Variables, optional snapshots to S3, optional agent metrics |
| [forgejo](packs/forgejo/README.md) | 0.2.0 | Forgejo (GPL-3.0-or-later, referenced, never shipped) as the internal git server and container registry: SQLite and repositories on a host volume, packages and LFS in RustFS, secrets from the built-in secret store, optional HTTPS, SSH, initial admin and periodic dumps; the Docker auth setup of the nodes; optional /metrics |
| [loadbalancer-operator](packs/loadbalancer-operator/README.md) | 0.4.0 | The LoadBalancer operator (norca-loadbalancer of norca-platform) as an operator pack: object kind (webhooks, limits), the LoadBalancerClass kind of the providers, ACL policy bound to the controller job, admission policy, controller job |
| [mtls-gateway](packs/mtls-gateway/README.md) | 0.2.1 | The cross-region native mTLS gateway of a region (`mtls { mode = "gateway" }`): SNI passthrough Envoy on the gateway nodes, injected by the servers or defined by the pack; optional Envoy statistics |
| [nats](packs/nats/README.md) | 0.7.0 | NATS cluster per region for the applications (JetStream, supercluster gateways, TLS and auth from Variables, or users in accounts with subject permissions and passwords from the built-in secret store), optional Prometheus exporter, the changes of the Norca region as a leaf node of the system bus |
| [nodescaler-operator](packs/nodescaler-operator/README.md) | 0.11.0 | The node scaling operator (norca-nodescaler) as an operator pack: ACL policy bound to its job (NodeGroup status and events, providers, the `nodescaler/` Variables, node write, reading jobs for the scale down), two instances with leader election, never on a node it created; optionally the join endpoint, where new nodes fetch and renew their certificates with keys of their own (norca-join), optionally kept in the TPM of the machine. Needs Norca 0.3.0 |
| [norca-acme](packs/norca-acme/README.md) | 0.2.0 | The ACME operator (norca-acme of norca-platform): the controller of the certificate issuers that sign through an ACME certificate authority such as Let's Encrypt; it fulfils the certificate orders of the servers, answers the HTTP-01 challenge behind the Traefik pack and proves names in the DNS zones of norca-provider; ACL policy bound to its job. Needs Norca 0.3.0 |
| [norca-dns](packs/norca-dns/README.md) | 0.2.0 | The DNS records operator (norca-dns of norca-platform): the norca.io/DNSRecord object kind and the controller that keeps their record sets (A, AAAA, CNAME, TXT; values given or from a LoadBalancer object) in the zones of norca-provider that allow records, under the allow list of each namespace; ACL policy bound to its job. Needs Norca 0.3.0 |
| [norca-provider](packs/norca-provider/README.md) | 0.5.0 | The provider application (norca-provider of norca-platform): one job serving the node providers of the node scaling operator, the load balancer classes of the LoadBalancer operator and the DNS zones of norca-acme and norca-dns its configuration names, registered as NodeProvider, LoadBalancerClass and DNSZone objects with a heartbeat; the DNSZone object kind; ACL policy bound to its job, secrets from its Variable. Needs Norca 0.3.0 |
| [openobserve](packs/openobserve/README.md) | 0.2.0 | OpenObserve (AGPL-3.0, referenced, never shipped) as the observability backend (logs, metrics, traces): single node on a host volume or a cluster of node roles on PostgreSQL, NATS (its own NATS user and account) and RustFS, TLS with Norca's workload certificates, root user and the ingest credentials of the collectors in the built-in secret store |
| [otel-collector](packs/otel-collector/README.md) | 0.1.2 | The OpenTelemetry Collector (contrib, Apache-2.0) on every node: host, Norca agent, NATS, RustFS, Forgejo, mTLS gateway, Consul and PostgreSQL metrics found through the native catalog, an OTLP receiver for the applications, export to OpenObserve with the ingest credentials of the secret store, trusting Norca's CA |
| [postgres](packs/postgres/README.md) | 0.1.0 | A single PostgreSQL server (PostgreSQL License, referenced, never shipped): data on a host volume, superuser, application databases and a `pg_monitor` role from the built-in secret store, optional TLS with Norca's workload certificates, optional periodic dumps to S3 |
| [rustfs](packs/rustfs/README.md) | 0.2.0 | RustFS (Apache-2.0) as the S3 store of the Norca backups: single node or distributed, credentials from the built-in secret store, host volumes, health check roles, optional bucket creation, optional OTLP metrics |
| [seaweedfs](packs/seaweedfs/README.md) | 0.1.0 | A single SeaweedFS server (Apache-2.0, release archive referenced, never shipped): master, volume server and filer in one weed process with raw_exec, data in a directory of the node, the services in the native catalog; the storage of the seaweedfs-csi pack |
| [seaweedfs-csi](packs/seaweedfs-csi/README.md) | 0.1.0 | The SeaweedFS CSI driver (Apache-2.0, fork with volume conditions; binaries referenced, never shipped) on every node with raw_exec: the mount service (weed mount, FUSE) and the driver as a monolith CSI plugin with volume statistics and conditions, the filer from the native catalog. Needs Norca 0.3.0 |
| [traefik](packs/traefik/README.md) | 0.3.0 | Traefik Proxy (MIT, the official image) as the edge router of a region: entrypoints for HTTP, HTTPS, TCP and UDP edited as a table in the install form, certificates from the built-in secret store applied without a restart, routes from the tags of the native catalog and static configuration; examples for web, WebSocket, gRPC and TCP. Needs Norca 0.3.0 |

The packs need Norca 0.1.0 or newer; packs with `requires` in their
`metadata.hcl` state the server features they use.

## Operator packs

The operator packs (loadbalancer-operator, nodescaler-operator, norca-acme,
norca-dns, norca-provider) run their jobs with ACL policies bound to them, in
the namespace `norca-system` by default, where their token Variables and
secrets are too. The packs expect the namespace and don't create it (a
namespace a release installs belongs to that release, and the packs share
it): create it once with `norca namespace apply -description "Norca
operators" norca-system`, and give rights in it to the operators of the
cluster only.

**They keep off nodes with the raw_exec driver** (review finding JOG-19): a
raw_exec task, or `alloc-node-exec`, on a node runs as the user of the agent
and reads the `secrets/` directory of every allocation of the node, so the
workload identity token of an operator and the ACL policies bound to its job.
Their jobs carry a constraint that `${attr.driver.raw_exec}` is not set (the
attribute a client with raw_exec enabled has), their default driver is
`exec` (the binary below `/usr`, in the chroot of `exec`), and they refuse
to render with `driver = "raw_exec"`. Run them on nodes without raw_exec
(a node pool of their own, `node_pool`), or set `allow_raw_exec_nodes =
true` where every token that may place raw_exec work or use
`alloc-node-exec` on those nodes may hold the operators' policies anyway (a
lab, a single-tenant cluster); the docker platform of norca-provider, which
calls the docker CLI of its host, needs it. The constraint is checked when
an allocation is placed: enabling raw_exec on a node later does not move an
operator that runs there.

## Using it

Add the registry once, pinned to a release tag, and use the packs by name:

```shell
norca pack registry add norca https://github.com/bacanoo-io/norca-registry --ref=v0.1.0
norca pack registry list

norca pack info   rustfs --registry=norca
norca pack render rustfs --registry=norca -f rustfs.hcl      # the jobs, without submitting them
norca pack plan   rustfs --registry=norca -f rustfs.hcl
norca pack run    rustfs --registry=norca -f rustfs.hcl
```

`--ref` takes a tag, a branch or a commit; without it the default branch is
used. Pack commands without `--ref` use the packs at the ref the registry was
last added or updated with, and without `--name` the release is named after
the pack. `--target=<pack>` downloads a single pack. `norca pack registry
update norca --ref=<tag>` moves the cache to another version, and
`norca pack registry delete norca` removes it.

From a checkout the packs can also be used by path, without a registry:

```shell
git clone https://github.com/bacanoo-io/norca-registry
norca pack run ./norca-registry/packs/nats -f nats.hcl
```

### On a cluster

The packs can also be installed from the Norca UI (Packages → Catalog): add
the repository as a cluster registry (Packages → Registries, type Git,
source `https://github.com/bacanoo-io/norca-registry`, reference a release
tag) and pick a sync interval. The servers fetch it, and the install form of
every pack is built from its `variables.hcl`. A release of this repository
can also notify a cluster so that it syncs at once (a push notice to its HTTP
API), see the notify job in [`release.yml`](.github/workflows/release.yml).

Example variable files for the packs are in [`examples/<pack>/`](examples);
the Norca repository's [deployment examples](https://github.com/bacanoo-io/norca/tree/main/example)
use the packs of this registry.

## Versions and tags

- Every pack has its own semantic version (`pack { version }` in
  `metadata.hcl`). A change that changes rendered jobs raises the patch
  version, new variables raise the minor version, renamed or removed
  variables and changed defaults that change a running installation raise the
  major version (`0.x`: the minor version).
- The registry is released as a whole with tags `vMAJOR.MINOR.PATCH`. A tag
  is never moved; pin it with `--ref`. `main` is the development branch and
  may change at any time.
- A registry release lists the pack versions it contains in its release notes.
  Pinned images (e.g. RustFS, NATS) change only with a pack version.
- Server releases (`norca pack run` against servers with the release API)
  record the pack name and version in the release; `norca pack history`
  shows which version each revision used.

For signed packs and air-gapped clusters, push the packs of a tag into an
internal OCI registry (`norca pack push`, `norca pack sign`) or carry them in
an offline bundle (`norca pack bundle create`); see
[supply chain](https://github.com/bacanoo-io/norca/blob/main/norca/pack/docs/supply-chain.md).

## Layout

```
README.md, LICENSE, REUSE.toml
packs/<name>/            one pack per directory (the layout "norca pack registry add" expects)
  metadata.hcl           name, version, requirements
  variables.hcl          variables with descriptions, defaults, validation blocks and rules
  templates/*.nomad.tpl  jobs; *.kind.hcl.tpl, *.acl.hcl.tpl, ... other resources
  templates/_*.tpl       helper templates
  outputs.tpl            text printed after a deployment
  README.md
examples/<name>/*.hcl    variable files, checked by scripts/check-packs.sh
scripts/check-packs.sh   local and CI checks
operators/<name>/        operators that aren't packs: Go source, a job and an engine to adapt
modules/<name>/          the module of Rigger converted from a pack (branch rigger)
  metadata.hcl           the module block: name, version, requirements
  variables.hcl          variables with their checks and rules
  <name>.norca.hcl       a job; <name>.acl.hcl, <name>.kind.hcl, ... other resources
  locals.hcl, modules.hcl  locals and the calls of child modules (lib/placement)
  outputs.hcl            outputs, the notes after an install among them
  examples/*.vars.hcl    values, rendered by rigger module validate
modules/lib/<name>/      library modules the others call
scripts/check-modules.sh, compare-packs.sh, check-modules-server.sh   the checks of the modules
```

## Contributing

Contributions are welcome: fixes, new variables, new packs for infrastructure
that runs on Norca. Every commit needs a DCO sign-off (`git commit -s`), like
the Norca repository.

- Write packs as described in Norca's
  [writing packs](https://github.com/bacanoo-io/norca/blob/main/norca/pack/docs/writing-packs.md)
  and [extended package format](https://github.com/bacanoo-io/norca/blob/main/norca/pack/docs/releases.md#extended-package-format):
  `[[ ]]` delimiters, `var "name" .` / `vars .` to read variables,
  `validation` blocks and `rule` blocks in `variables.hcl` for anything the
  variable types can't express.
- New files carry the SPDX header `SPDX-FileCopyrightText: 2026 Norca
  contributors` / `SPDX-License-Identifier: MPL-2.0` (`#` comments in HCL, a
  `[[/* ... */]]` comment in templates whose output is printed, `$comment` in
  JSON); the packs are MPL-2.0 ([LICENSE](LICENSE)).
- Packs reference third-party software (images, release archives) by name,
  tag and optionally digest; they never include it. Pin images to a release
  that is at least two weeks old, state its license in the pack README, and
  take secrets from the built-in secret store or Variables, never from pack
  variables.
- Every pack needs a README (what it deploys, prerequisites, variables,
  checks, limitations) and at least one variable file in `examples/<pack>/`
  if its defaults don't cover the main use.
- Check before a pull request, with a `norca` binary built from the Norca
  repository (`cd nomad && go build -o ~/bin/norca .`):

  ```shell
  NORCA=~/bin/norca scripts/check-packs.sh          # all packs
  NORCA=~/bin/norca scripts/check-packs.sh rustfs   # one pack
  norca pack fmt -recursive ./packs/<pack>          # format
  ```

  The script runs `norca pack fmt -check`, renders every pack with its
  defaults and every file in `examples/<pack>/` (which also checks the
  variables schema), and validates the rendered jobs with `norca job validate`
  without an agent. Run `norca pack plan` against a test cluster for what local
  validation can't check (drivers, the tasks the servers inject).

The [CI workflow](.github/workflows/check.yml) runs the same script with a
`norca` built from the Norca sources, and `reuse lint`.

## License

The packs and the documentation of this registry are licensed under the
Mozilla Public License 2.0 ([LICENSE](LICENSE)). The software the packs
install keeps its own license (see each pack's README); Consul in particular
is BSL 1.1, Forgejo GPL-3.0-or-later and OpenObserve AGPL-3.0, and none of
them is distributed by this registry.
