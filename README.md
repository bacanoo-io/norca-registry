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

| Pack | Version | |
| --- | --- | --- |
| [consul](packs/consul/README.md) | 0.2.0 | Installs and manages the official HashiCorp Consul release (BSL 1.1, referenced, never shipped; accepted by the user at install): servers on host volumes over zones, client agents, gossip/TLS/ACL bootstrap from Variables, optional snapshots to S3, optional agent metrics |
| [forgejo](packs/forgejo/README.md) | 0.2.0 | Forgejo (GPL-3.0-or-later, referenced, never shipped) as the internal git server and container registry: SQLite and repositories on a host volume, packages and LFS in RustFS, secrets from the built-in secret store, optional HTTPS, SSH, initial admin and periodic dumps; the Docker auth setup of the nodes; optional /metrics |
| [loadbalancer-operator](packs/loadbalancer-operator/README.md) | 0.1.0 | The LoadBalancer operator as an operator pack: object kind (webhooks, limits), ACL policy bound to the controller job, admission policy, controller job |
| [mtls-gateway](packs/mtls-gateway/README.md) | 0.2.1 | The cross-region native mTLS gateway of a region (`mtls { mode = "gateway" }`): SNI passthrough Envoy on the gateway nodes, injected by the servers or defined by the pack; optional Envoy statistics |
| [nats](packs/nats/README.md) | 0.3.0 | NATS cluster per region (JetStream, supercluster gateways, TLS and auth from Variables, or users in accounts with subject permissions and passwords from the built-in secret store) and the event stream → NATS bridge, optional Prometheus exporter |
| [openobserve](packs/openobserve/README.md) | 0.2.0 | OpenObserve (AGPL-3.0, referenced, never shipped) as the observability backend (logs, metrics, traces): single node on a host volume or a cluster of node roles on PostgreSQL, NATS (its own NATS user and account) and RustFS, TLS with Norca's workload certificates, root user and the ingest credentials of the collectors in the built-in secret store |
| [otel-collector](packs/otel-collector/README.md) | 0.1.1 | The OpenTelemetry Collector (contrib, Apache-2.0) on every node: host, Norca agent, NATS, RustFS, Forgejo, mTLS gateway, Consul and PostgreSQL metrics found through the native catalog, an OTLP receiver for the applications, export to OpenObserve with the ingest credentials of the secret store, trusting Norca's CA |
| [postgres](packs/postgres/README.md) | 0.1.0 | A single PostgreSQL server (PostgreSQL License, referenced, never shipped): data on a host volume, superuser, application databases and a `pg_monitor` role from the built-in secret store, optional TLS with Norca's workload certificates, optional periodic dumps to S3 |
| [rustfs](packs/rustfs/README.md) | 0.2.0 | RustFS (Apache-2.0) as the S3 store of the Norca backups: single node or distributed, credentials from the built-in secret store, host volumes, health check roles, optional bucket creation, optional OTLP metrics |

The packs need Norca 0.1.0 or newer; packs with `requires` in their
`metadata.hcl` state the server features they use.

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
[supply chain](https://github.com/bacanoo-io/norca/blob/main/nomad/pack/docs/supply-chain.md).

## Layout

```
README.md, LICENSE, REUSE.toml
packs/<name>/            one pack per directory (the layout "norca pack registry add" expects)
  metadata.hcl           name, version, requirements, variables_schema
  variables.hcl          variables with descriptions and defaults
  values.schema.json     JSON Schema of the variable values (optional)
  templates/*.nomad.tpl  jobs; *.kind.hcl.tpl, *.acl.hcl.tpl, ... other resources
  templates/_*.tpl       helper templates
  outputs.tpl            text printed after a deployment
  README.md
examples/<name>/*.hcl    variable files, checked by scripts/check-packs.sh
scripts/check-packs.sh   local and CI checks
```

## Contributing

Contributions are welcome: fixes, new variables, new packs for infrastructure
that runs on Norca. Every commit needs a DCO sign-off (`git commit -s`), like
the Norca repository.

- Write packs as described in Norca's
  [writing packs](https://github.com/bacanoo-io/norca/blob/main/nomad/pack/docs/writing-packs.md)
  and [extended package format](https://github.com/bacanoo-io/norca/blob/main/nomad/pack/docs/releases.md#extended-package-format):
  `[[ ]]` delimiters, `var "name" .` / `vars .` to read variables, a
  `values.schema.json` for anything the variable types can't express.
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
