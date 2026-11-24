<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# nodescaler-operator

The node scaling operator of Norca, `norca-nodescaler` of
[norca-platform](https://github.com/bacanoo-io/norca-platform), as one
release:

- the ACL policy of the operator, bound to its job: the status, the event
  log and the finalizer of the `norca.io/NodeGroup` objects (not their spec;
  the finalizer keeps a deleted group until its instances are dealt with by
  its `spec.deletion`), reading the `norca.io/NodeProvider` objects and
  writing their event log (orphaned instances are reported there), the
  Variables under `nodescaler/` (the
  bootstrap and the network ranges of the region, the tokens of the
  providers), its leader election lease, node write (a foreign node is made
  ineligible; a scale down drains a node, makes it eligible again and purges
  it once down; an edge node is marked `norca.lb.leaving` before its drain),
  reading the jobs of every namespace (a scale down checks that the
  allocations of a node could be placed again), and reading the
  `norca.io/LoadBalancer` objects of every namespace (an edge node waits until
  its load balancers dropped it);
- the job: two instances on different nodes, and in different datacenters
  where there are several (a spread), with leader election, in a node
  pool of its own choice, and **never on a node the operator created**
  (`${meta.norca.instance}` must not be set), so it cannot delete the machine
  it runs on;
- with `join_enabled`, the **join endpoint** on a static port and the service
  `<job_name>-join`: the bootstrap of a new node carries a one-time token
  instead of its key and certificate, and `norca-join` on the machine makes
  the key, fetches the certificate and renews it (the policy then also
  writes and deletes the records under `nodescaler/join/`). The endpoint
  accepts a join or a renewal only from an address the provider reports
  for the instance (`join_check_address`), and a renewal only with a new
  key. With `join_key_store` (or `spec.join.key_store` of a group) the key
  of a node is made in the TPM 2.0 of its machine and never leaves it.

The kinds `NodeGroup` and `NodeProvider` are registered by the core; the
providers are applications of their own and register themselves, for example
`norca-provider` (the [norca-provider](../norca-provider) module).

## Before

- The namespace of the operator: the namespace of the release
  (`-namespace`), `norca-system` for the operator modules of this registry,
  an operations namespace they share. The module expects it and does not
  create it (a namespace a release installs belongs to that release, which
  would delete it on uninstall and conflict with the other operator
  modules); create it once:
  `norca namespace apply -description "Norca operators" norca-system`.
  Give rights in it to the operators of the cluster only: the job runs there
  with the ACL policy bound to it (node write among others), and the
  bootstrap Variable holds the key of the node CA.
- `node_scaling` in the plan of norca-deployer, with `namespace:
  norca-system` (the namespace of the Variables the operator reads), and a
  node CA (`norca-deployer pki issue-node-ca`): `apply` writes
  `nodescaler/bootstrap/<region>` and `nodescaler/network/<region>`.
- The binary on the nodes of the pool (`/usr/local/bin/norca-nodescaler`), or
  an image (`driver = "docker"`).
- Nodes without the raw_exec driver: the job keeps off nodes with it unless
  `allow_raw_exec_nodes = true`, and its default driver is `exec`; see
  [operator packs](../../README.md#operator-packs) (review finding JOG-19).

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `job_name` | `nodescaler` | The job; the policy is bound to it. |
| the namespace of the release (`-namespace`) | `norca-system` in the install below | Namespace of the job and of the lease; it must exist. The module has no variable for it. |
| `region`, `datacenters` | the release's, `["*"]` | Where the job runs; one operator per region. |
| `node_pool` | `default` | Run it outside the pools it scales. |
| `count` | `2` | Instances, on different nodes and, where there are several, in different datacenters: when a datacenter is lost the operator must still be there to add nodes in the others. |
| `driver`, `binary`, `image` | `exec`, `/usr/local/bin/norca-nodescaler` | How the binary runs; `raw_exec` only with `allow_raw_exec_nodes`. |
| `allow_raw_exec_nodes` | `false` | Allow nodes with the raw_exec driver and `driver = "raw_exec"` (JOG-19). |
| `cpu`, `memory`, `log_level` | `100`, `64`, `info` | |
| `variables_namespace` | `""` | Namespace of the Variables under `nodescaler/`; empty: the namespace of the job. `node_scaling.namespace` of norca-deployer must name the same one. |
| `provider_ttl` | `3m` | How old the heartbeat of a provider may be. |
| `provider_allow_http` | `false` | http endpoints of providers (labs only). |
| `resync` | `5m` | Period of the full resynchronization of the groups. |
| `orphan_after` | `15m` | Age after which an orphaned instance without a node is deleted. |
| `orphan_sweep` | `5m` | How often the leader looks for orphaned instances at the providers. |
| `delete_orphans` | `false` | Delete orphaned instances that run a node too; otherwise they are only reported. |
| `join_enabled` | `false` | Serve the join endpoint: the nodes make their own keys (`norca-join` on the machines, the bootstrap item `join_binary`). |
| `join_port` | `8490` | Static port of the join endpoint; the new nodes must reach it. The service `<job_name>-join` is checked on it over https (`GET /v1/health`, `tls_skip_verify`: the node CA issued its certificate), which needs a Norca with `tls_skip_verify` on the checks of Norca services. |
| `join_validity` | `168h` | Validity of the certificate of a node that renews itself (at two thirds). |
| `join_urls` | `[]` | Stable https URLs of the endpoint (a DNS name, a load balancer); empty: the instances of the service `<job_name>-join`. |
| `join_check_address` | `true` | Accept a join or a renewal only from an address the provider reports for the instance; a request from another one is refused and is a `JoinAddressRefused` warning in the log of the group. Set `false` where a proxy, a load balancer or NAT in front of the endpoint changes the source address (`join_urls` behind such a load balancer). A provider that reports no addresses has no binding. |
| `join_key_store` | `file` | Where the nodes keep their keys, unless their group sets `spec.join.key_store`: `file` (a key file), `tpm` (made in the TPM 2.0 of the machine, which must have `/dev/tpmrm0`; the key never leaves it and the key file is useless elsewhere; Linux) or `auto` (the TPM where the machine has one, else a file). On clouds: a vTPM (Shielded VM, Trusted Launch, NitroTPM). |

```shell
norca module plan nodescaler-operator --registry=norca
norca module run  nodescaler-operator --registry=norca --var=node_pool=system
```

## Install

```shell
rigger install ./modules/nodescaler-operator -name nodescaler -namespace norca-system
```

Outputs: `job`, `join_service` and `notes`. The ACL policy is the resource `operator`. `driver = "raw_exec"` without `allow_raw_exec_nodes = true` is refused by the rule `raw_exec` (the `fail` of the pack); `examples/raw-exec.vars.hcl` is the allowed way.

## From the pack

Converted from the pack `nodescaler-operator` 0.11.0 with `rigger convert pack`; for the
defaults and every example it renders the jobs and other resources of the
pack (`scripts/compare-packs.sh nodescaler-operator`). The job ID is `job_name`, as in the pack. The namespace and the region are
the release's.
