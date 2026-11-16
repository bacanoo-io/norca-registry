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
| `dns.acl.hcl.tpl` | ACL policy bound to the job (`job_acl`): `read`, `write-status`, `write-events` and `manage-finalizers` on `norca.io/DNSRecord`, `read` on `norca.io/LoadBalancer` and `norca.io/DNSZone`, `read-job` for the metadata of the namespaces, the token Variables of the DNS zones |
| `dns.nomad.tpl` | The job: one instance, never on a node the node scaling operator created |

## Before

- The binary on the nodes (`/usr/local/bin/norca-dns`, built in a
  norca-platform checkout with `go build -o norca-dns ./cmd/norca-dns`), or
  an image (`driver = "docker"`).
- A provider of the [norca-provider](../norca-provider) pack (0.4.0 or
  later) with a `dns` section for the zone and **`"records": true`** on the
  zone, of a type that can write records (`rfc2136`, `mock`).
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

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `requeue` | `5m` | Time after which a record is compared with its zone again; a change made by hand is set back then. |
| `zone_token_namespace`, `zone_token_path` | `default`, `providers/*` | Where the tokens of the DNS zones are. |
| `zone_ttl` | `3m` | How old the heartbeat of a zone may be. |
| `zone_allow_http` | `false` | Accept http endpoints of zones (labs only). |
| `zone_ca_cert` | | The CA of the https certificates of the DNS providers. |

See [Variables](variables.hcl) for the job settings.

## Limits

- One cluster writes a zone: the zone carries no marker of which records
  are whose.
- Values from a service's nodes are not a source (a later version): the
  nodes of a service change with every placement.
