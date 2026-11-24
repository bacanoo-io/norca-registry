<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# norca-dns

The DNS records operator of Norca, `norca-dns` of
[norca-platform](https://github.com/bacanoo-io/norca-platform), as one
release. It is the controller of the `norca.io/DNSRecord` objects: DNS
names that follow what runs in the cluster.

A `DNSRecord` declares one record set (a name, a type, its values); the
operator keeps it in the zone of [norca-provider](../norca-provider) that
holds the name. **It changes only the record sets it wrote**, writes only
the names a namespace may write, and only in zones that allow it.

| Template | Resource |
| --- | --- |
| `dnsrecord.kind.hcl.tpl` | The `norca.io/DNSRecord` object kind (`record_kind_enabled`) |
| `dns.acl.hcl.tpl` | ACL policy bound to the job (`job_acl`): `read`, `write-status`, `write-events` and `manage-finalizers` on `norca.io/DNSRecord`, `read` on `norca.io/LoadBalancer` and `norca.io/DNSZone`, `read-job` for the metadata of the namespaces (`list-jobs` in the namespace of the tokens, whose block stands in for the `*` block there), the token Variables of the DNS zones |
| `dns.nomad.tpl` | The job: one instance, never on a node the node scaling operator created |

## Before

- The namespace of the operator: the namespace of the release
  (`-namespace`), `norca-system` for the operator modules of this registry,
  an operations namespace they share. The module expects it and does not
  create it (a namespace a release installs belongs to that release, which
  would delete it on uninstall and conflict with the other operator
  modules); create it once:
  `norca namespace apply -description "Norca operators" norca-system`.
  Give rights in it to the operators of the cluster only: the job runs there
  with the ACL policy bound to it, and the tokens of the DNS zones are
  Variables of it by default.
- The binary on the nodes (`/usr/local/bin/norca-dns`, built in a
  norca-platform checkout with `go build -o norca-dns ./cmd/norca-dns`), or
  an image (`driver = "docker"`).
- Nodes without the raw_exec driver: the job keeps off nodes with it unless
  `allow_raw_exec_nodes = true`, and its default driver is `exec`; see
  [operator packs](../../README.md#operator-packs) (review finding JOG-19).
- A provider of the [norca-provider](../norca-provider) module (0.4.0 or
  later) with a `dns` section for the zone and **`"records": true`** on the
  zone, of a type that can write records (`rfc2136`, `mock`), and the token
  of the zone in the Variable its `token_variable` names, in
  `zone_token_namespace`:
  `norca var put -namespace norca-system providers/dns-eu token=...`.
- The allow list of each namespace that writes names: the namespace
  metadata `norca.io/dns-suffixes` (comma separated), or `dns_suffixes` of
  its `Tenant`.

## A record

```hcl
kind      = "norca.io/DNSRecord"
name      = "shop"
namespace = "team-a"

spec {
  name   = "shop.team-a.example.com"
  type   = "A"
  ttl    = 300
  values = ["203.0.113.10"]
}
```

Or the addresses of a load balancer of the namespace:

```hcl
spec {
  name   = "shop.team-a.example.com"
  type   = "A"
  source { load_balancer = "shop" }
}
```

| Field | Meaning |
| --- | --- |
| `name` | Fully qualified name. |
| `type` | `A`, `AAAA`, `CNAME` or `TXT`. |
| `ttl` | Seconds; 0 or unset is 300. |
| `values` | The values: addresses, one name for a CNAME, texts. |
| `source.load_balancer` | A `LoadBalancer` object of the namespace: its frontend addresses (A: IPv4, AAAA: IPv6, CNAME: its first host name). |
| `adopt` | Take over a record set of the name and type that norca-dns did not write. |
| `deletion_policy` | `delete` (default): deleting the record removes its record set, and the record stays until that succeeds. `retain`: the set stays in the zone; setting it on a record whose deletion is stuck lets the deletion finish. |

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| the namespace of the release (`-namespace`) | `norca-system` in the install below | Namespace of the job; it must exist. The module has no variable for it. |
| `requeue` | `5m` | Time after which a record is compared with its zone again; a change made by hand is set back then. More than zero. |
| `zone_token_namespace`, `zone_token_path` | `""`, `providers/*` | Where the tokens of the DNS zones are; an empty namespace is the namespace of the job. |
| `zone_ttl` | `3m` | How old the heartbeat of a zone may be. More than zero. |
| `zone_allow_http` | `false` | Accept http endpoints of zones (labs only). |
| `zone_ca_cert` | | The CA of the https certificates of the DNS providers. |

See [Variables](variables.hcl) for the job settings.

## Limits

- One cluster writes a zone: the zone carries no marker of which records
  are whose.
- Values from a service's nodes are not a source (a later version): the
  nodes of a service change with every placement.

## Install

```shell
norca namespace apply -description "Norca operators" norca-system   # once
rigger install ./modules/norca-dns -name norca-dns -namespace norca-system
```

Outputs: `job` and `notes`. The kind `norca.io/DNSRecord` is the resource `dns-record`, the ACL policy `dns`; `record_kind_enabled` and `acl_policy_enabled` leave them out. `driver = "raw_exec"` without `allow_raw_exec_nodes = true` is refused by the rule `raw_exec` (the `fail` of the pack); `examples/raw-exec.vars.hcl` is the allowed way.

## From the pack

Converted from the pack `norca-dns` 0.2.0 with `rigger convert pack`; for the
defaults and every example it renders the jobs and other resources of the
pack (`scripts/compare-packs.sh norca-dns`). The job ID is `job_name`, as in the pack. The namespace and the region are
the release's.
