<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# Norca registry

The public module registry of [Norca](https://github.com/bacanoo-io/norca):
the modules of [Rigger](https://github.com/bacanoo-io/norca/tree/main/rigger),
Norca's package manager, that install the infrastructure around a Norca
cluster (NATS, the cross-region mTLS gateway, the backup store, the git
server and image registry, PostgreSQL, observability with OpenObserve and the
OpenTelemetry Collector, the edge router, optional Consul) and the operator
modules. A module holds object kinds, ACL and admission policies next to its
jobs, and `validation` blocks and rules for its variables, which also build
its install form in the web UI.

Each module has its own version and is released by a signed tag
`<module>/v<version>`. The
[global registry](https://github.com/bacanoo-io/norca-global-registry) of
Rigger lists the released versions as `norca/<module>`. See the
[Norca registry](https://github.com/bacanoo-io/norca-doc/blob/main/content/docs/features/packages/registry.md)
in the documentation for an overview of every module.

## Modules

| Module | Version | |
| --- | --- | --- |
| [consul](modules/consul/README.md) | 0.3.1 | The official HashiCorp Consul release (BSL 1.1, referenced, never shipped; accepted by the user at install): servers, client agents, gossip, TLS and ACL bootstrap, optional snapshots to S3 |
| [forgejo](modules/forgejo/README.md) | 0.2.1 | Forgejo (GPL-3.0-or-later, referenced, never shipped) as the internal git server and container registry |
| [loadbalancer-operator](modules/loadbalancer-operator/README.md) | 0.5.1 | The LoadBalancer operator: its object kinds, ACL and admission policies and the controller job |
| [mtls-gateway](modules/mtls-gateway/README.md) | 0.2.2 | The cross-region native mTLS gateway of a region: an SNI passthrough Envoy on the gateway nodes |
| [nats](modules/nats/README.md) | 2.0.1 | A NATS cluster per region for the applications: JetStream, supercluster gateways, TLS, users in accounts |
| [nats-demo](modules/nats-demo/README.md) | 1.0.0 | A demonstration of the language of the modules: a NATS cluster in a smaller shape |
| [nodescaler-operator](modules/nodescaler-operator/README.md) | 0.11.1 | The node scaling operator: its ACL policy and job, and optionally the join endpoint of new nodes |
| [norca-acme](modules/norca-acme/README.md) | 0.3.1 | The ACME operator: certificate issuers that sign through an ACME certificate authority such as Let's Encrypt |
| [norca-dns](modules/norca-dns/README.md) | 0.3.1 | The DNS records operator: the `norca.io/DNSRecord` kind and the controller that keeps the record sets |
| [norca-provider](modules/norca-provider/README.md) | 0.5.1 | The provider application: node providers, load balancer classes and DNS zones of its configuration |
| [openobserve](modules/openobserve/README.md) | 0.2.2 | OpenObserve (AGPL-3.0, referenced, never shipped) as the observability backend: a single node or a cluster |
| [otel-collector](modules/otel-collector/README.md) | 0.2.0 | The OpenTelemetry Collector on every node: host, agent and service metrics (scraped or pushed over OTLP), OTLP, export to OpenObserve |
| [postgres](modules/postgres/README.md) | 0.4.1 | A single PostgreSQL server: databases and roles from the secret store, optional TLS and dumps to S3 |
| [postgres-demo](modules/postgres-demo/README.md) | 0.3.1 | A demonstration of the language of the modules: a single PostgreSQL server |
| [redis](modules/redis/README.md) | 0.4.2 | One Redis server with a password the server requires and optional persistence |
| [rustfs](modules/rustfs/README.md) | 0.2.1 | RustFS (Apache-2.0) as the S3 store of the Norca backups: single node or distributed |
| [seaweedfs](modules/seaweedfs/README.md) | 0.1.1 | A single SeaweedFS server (Apache-2.0, referenced, never shipped): the storage of seaweedfs-csi |
| [seaweedfs-csi](modules/seaweedfs-csi/README.md) | 0.1.1 | The SeaweedFS CSI driver on every node: the mount service and the CSI plugin |
| [traefik](modules/traefik/README.md) | 0.3.2 | Traefik Proxy (MIT) as the edge router of a region: entrypoints, certificates, routes from the catalog |
| lib/placement | 1.1.0 | A library the other modules call for the placement of a job and the reference of an image; not installed on its own |

Each module's README describes what it deploys, its prerequisites, its
variables, its checks and its limitations. A module states the Norca version
and the server features it needs in the `requires` block of its
`metadata.hcl`.

## Installing a module

The servers install a module of the global registry by its name, from the
registry as they last synced it. Nothing syncs on its own: sync the global
registry once in every region, then send the install to the servers:

```shell
norca rigger registry sync global
norca rigger registry search global rustfs -kind module

norca operator api -X PUT /v1/rigger/install <<'EOF'
{"Release": "rustfs", "Registry": "global", "Module": "norca/rustfs", "Version": "~> 0.2",
 "ValuesJSON": {"buckets": ["norca-backup"], "console_enabled": true}}
EOF
norca rigger release status rustfs
```

The servers take the newest version of the last sync that meets `Version`,
fetch it from this repository and refuse it unless it has the tree digest
the global registry lists and a signature by the key of the namespace
`norca`. `ValuesJSON` holds the values of the module's variables, each with
the JSON type of its variable. The release is in the namespace and the
region of the request (`-namespace` and `-region` of `norca operator api`):
a module has no `namespace` variable. One request installs one release in
one region; a module that runs in several regions is installed once per
region. The same request with other values upgrades the release.

A **stack** names modules of the global registry by their source, and
Rigger installs them as releases and keeps their versions in a lock file:

```hcl
rigger {
  name = "operations"
}

module "rustfs" {
  source  = "norca/rustfs"
  version = "~> 0.2"

  values = {
    buckets         = ["norca-backup"]
    console_enabled = true
  }
}
```

```shell
norca rigger stack sync .     # resolve the versions, fetch and verify the modules, write rigger.lock.hcl
norca rigger stack plan .     # what an apply would change
norca rigger stack apply .    # install or upgrade, release after release
```

**From a checkout** of this registry a module installs by its path, without
the global registry. `norca rigger install` takes a directory, `-f` a file of
values (each module has examples in `modules/<module>/examples/*.vars.hcl`):

```shell
git clone https://github.com/bacanoo-io/norca-registry
norca rigger install norca-registry/modules/rustfs -name rustfs \
  -f norca-registry/modules/rustfs/examples/single-node.vars.hcl
norca rigger module render norca-registry/modules/rustfs -f values.vars.hcl   # the resources, without a cluster
```

The web UI installs the modules of a synced registry too (**Packages →
Catalog**), with a form built from the variables of the module. `rigger` is
the same program as `norca rigger`. The Norca repository's
[deployment examples](https://github.com/bacanoo-io/norca/tree/main/example)
use the modules of this registry.

## Operator modules

loadbalancer-operator, nodescaler-operator, norca-acme, norca-dns and
norca-provider run their jobs with ACL policies bound to them. Their jobs,
the ACL policies bound to them and, by default, their token Variables and
secrets are in the namespace of the release, so install them with
`-namespace norca-system`. The modules expect the namespace and don't create
it (a namespace a release installs belongs to that release, and the modules
share it): create it once with `norca namespace apply -description "Norca
operators" norca-system`, and give rights in it to the operators of the
cluster only.

**They keep off nodes with the raw_exec driver** (review finding JOG-19): a
raw_exec task, or `alloc-node-exec`, on a node runs as the user of the agent
and reads the `secrets/` directory of every allocation of the node, so the
workload identity token of an operator and the ACL policies bound to its job.
Their jobs carry a constraint that `${attr.driver.raw_exec}` is not set (the
attribute a client with raw_exec enabled has), their default driver is
`exec` (the binary below `/usr`, in the chroot of `exec`), and the rule
`raw_exec` of each module refuses `driver = "raw_exec"`; the tests of each
of the five modules check it. Run them on nodes without raw_exec (a node
pool of their own, `node_pool`), or set `allow_raw_exec_nodes = true` where
every token that may place raw_exec work or use `alloc-node-exec` on those
nodes may hold the operators' policies anyway (a lab, a single-tenant
cluster); the docker platform of norca-provider, which calls the docker CLI
of its host, needs it. The constraint is checked when an allocation is
placed: enabling raw_exec on a node later does not move an operator that
runs there.

## Versions and releases

- Every module has its own semantic version (`module { version }` in
  `metadata.hcl`). Every file of a module is part of its tree digest, so any
  change of a module, its README and its examples included, is a new
  version. New variables raise the minor version; renamed or removed
  variables and changed defaults that change a running installation raise
  the major version (`0.x`: the minor version); any other change raises the
  patch version.
- A version is released by the tag `<module>/v<version>` (`nats/v2.0.1`),
  which is never moved. `main` is the development branch and may change at
  any time.
- Pinned images (e.g. RustFS, NATS) change only with a module version.

A maintainer releases the versions that have no tag yet with the signing key
of the namespace `norca`:

1. Check the branch: no uncommitted change, nothing of the remote branch
   missing.
2. For every module whose version has no tag, `rigger module publish
   modules/<module> -key norca.key` (the password of the key in
   `RIGGER_KEY_PASSWORD`) signs the tree digest of the module into its
   `.rigger-signatures` directory, commits the signature and tags the
   version. It pushes nothing.
3. `rigger key verify modules/<module> -key norca.pub` checks every
   signature with the public key of the namespace.
4. The branch and the new tags are pushed together, in one atomic push.

The *Update* workflow of the global registry then lists every new tag once
it passes the checks there. `lib/placement` has no tag of its own: the
modules read it from their own tag of this repository.

## Checks

With the `rigger` program on the PATH (or `RIGGER=<path of the program>`):

- `scripts/check-modules.sh`: `rigger fmt -check`, `rigger module validate`
  (the files, the defaults and the example values rendered through Norca's
  job decoder) and `rigger module test` of every module.
- `scripts/check-modules-server.sh [module...]`: every job the modules
  render, for the defaults and every example, passes the validation of a
  Norca server (`PUT /v1/validate/job`; `NORCA_ADDR`, `NORCA_TOKEN`,
  `CREATE_NODE_POOLS=1` on a throwaway dev agent).

The [CI workflow](.github/workflows/check.yml) builds `rigger` from the Norca
sources and runs `scripts/check-modules.sh`, and tests the operators of
`operators/`; the [compliance workflow](.github/workflows/compliance.yml)
runs `reuse lint` and checks the DCO sign-offs.

## Layout

```
README.md, LICENSE, REUSE.toml
modules/<name>/            one module per directory
  metadata.hcl             the module block: name, version, requirements
  variables.hcl            variables with their checks and rules
  <name>.norca.hcl         a job; <name>.acl.hcl, <name>.kind.hcl, ... other resources
  locals.hcl, modules.hcl  locals and the calls of child modules (lib/placement)
  outputs.hcl              outputs, the notes after an install among them
  examples/*.vars.hcl      values, rendered by rigger module validate
  tests/*.riggertest.hcl   tests, run by rigger module test
  .rigger-signatures/      the signatures of the released versions
  README.md
modules/lib/<name>/        library modules the others call
operators/<name>/          operators that aren't modules: Go source, a job and an engine to adapt
scripts/                   the checks of the modules
```

## Contributing

Contributions are welcome: fixes, new variables, new modules for
infrastructure that runs on Norca. Every commit needs a DCO sign-off
(`git commit -s`), like the Norca repository.

- Write modules as described in Norca's
  [modules and stacks](https://github.com/bacanoo-io/norca-doc/blob/main/content/docs/features/packages/modules.md):
  `validation` blocks and `rule` blocks in `variables.hcl` for anything the
  variable types can't express, tests in `tests/`, example values in
  `examples/`.
- A changed module gets a new version (see
  [Versions and releases](#versions-and-releases)) and its row in the table
  above.
- New files carry the SPDX header `SPDX-FileCopyrightText: 2026 Norca
  contributors` / `SPDX-License-Identifier: MPL-2.0` (`#` comments in HCL);
  the modules are MPL-2.0 ([LICENSE](LICENSE)).
- Modules reference third-party software (images, release archives) by name,
  tag and optionally digest; they never include it. Pin images to a release
  that is at least two weeks old, state its license in the module README,
  and take secrets from the built-in secret store or Variables, never from
  module variables.
- Every module needs a README (what it deploys, prerequisites, variables,
  checks, limitations) and example values in `examples/` if its defaults
  don't cover the main use.
- Check before a pull request, with a `rigger` program built from the Norca
  repository (`go -C rigger/cli build -o ~/bin/rigger ./cmd/rigger`):

  ```shell
  RIGGER=~/bin/rigger scripts/check-modules.sh
  ~/bin/rigger fmt modules/<module>               # format
  ```

  Run `scripts/check-modules-server.sh <module>` against a test cluster for
  what the decoder of rigger can't check.

## License

The modules and the documentation of this registry are licensed under the
Mozilla Public License 2.0 ([LICENSE](LICENSE)). The software the modules
install keeps its own license (see each module's README); Consul in
particular is BSL 1.1, Forgejo GPL-3.0-or-later and OpenObserve AGPL-3.0,
and none of them is distributed by this registry.
