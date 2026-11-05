<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# nodescaler-operator

The node scaling operator of Norca, `norca-nodescaler` of
[norca-platform](https://github.com/bacanoo-io/norca-platform), as one
release:

- the ACL policy of the operator, bound to its job: the status and the event
  log of the `norca.io/NodeGroup` objects (not their spec), reading the
  `norca.io/NodeProvider` objects, the Variables under `nodescaler/` (the
  bootstrap and the network ranges of the region, the tokens of the
  providers), its leader election lease, and node write (a foreign node is
  made ineligible);
- the job: two instances on different nodes with leader election, in a node
  pool of its own choice, and **never on a node the operator created**
  (`${meta.norca.instance}` must not be set), so it cannot delete the machine
  it runs on.

The kinds `NodeGroup` and `NodeProvider` are registered by the core; the
providers are applications of their own and register themselves.

## Before

- `node_scaling` in the plan of norca-deployer and a node CA
  (`norca-deployer pki issue-node-ca`): `apply` writes
  `nodescaler/bootstrap/<region>` and `nodescaler/network/<region>`.
- The binary on the nodes of the pool (`/usr/local/bin/norca-nodescaler`), or
  an image (`driver = "docker"`).

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `job_name` | `nodescaler` | The job; the policy is bound to it. |
| `namespace` | `default` | Namespace of the job and of the lease. |
| `region`, `datacenters` | the release's, `["*"]` | Where the job runs; one operator per region. |
| `node_pool` | `default` | Run it outside the pools it scales. |
| `count` | `2` | Instances, on different nodes. |
| `driver`, `binary`, `image` | `raw_exec`, `/usr/local/bin/norca-nodescaler` | How the binary runs. |
| `cpu`, `memory`, `log_level` | `100`, `64`, `info` | |
| `variables_namespace` | `default` | Namespace of the Variables under `nodescaler/`. |
| `provider_ttl` | `3m` | How old the heartbeat of a provider may be. |
| `provider_allow_http` | `false` | http endpoints of providers (labs only). |
| `orphan_after` | `15m` | Age after which an orphaned instance without a node is deleted. |

```shell
norca pack plan nodescaler-operator --registry=norca
norca pack run  nodescaler-operator --registry=norca --var=node_pool=system
```
