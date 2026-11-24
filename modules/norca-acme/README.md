<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# norca-acme

The ACME operator of Norca, `norca-acme` of
[norca-platform](https://github.com/bacanoo-io/norca-platform), as one
release. It is the controller of the certificate issuers that sign through
an ACME certificate authority (RFC 8555), such as Let's Encrypt.

The servers keep the certificates: a `norca.io/Certificate` object names an
issuer, the servers make the key and the signing request, write the secret
and renew it. For an issuer of this operator they hand the signing request
over in a `norca.io/CertificateOrder`; the operator places the order with
the certificate authority, proves the names, and writes the chain back.
**It never sees a private key of a certificate and reads no secret of a
namespace.**

| Template | Resource |
| --- | --- |
| `acme.acl.hcl.tpl` | ACL policy bound to the job (`job_acl`): `read` and `write-status` on `norca.io/CertificateIssuer` and `norca.io/CertificateOrder`, `read` on `norca.io/DNSZone` (cluster-scoped, so in the namespace `"*"`), the secrets below `secret_prefix`, the token Variables of the DNS zones; with leader election `read` and `write` on the lease, the Variable `controller-lease/<controller>` in `lease_namespace` |
| `acme.nomad.tpl` | The job: one instance, or several on different nodes with leader election (`count`, `leader_election`), never on a node the node scaling operator created; a service that answers the HTTP-01 challenge, with the router of the Traefik module as catalog tags, and with leader election a check on `/readyz` that only the instance that leads passes |

## Before

- The namespace of the operator: the namespace of the release
  (`-namespace`), `norca-system` for the operator modules of this registry,
  an operations namespace they share. The module expects it and does not
  create it (a namespace a release installs belongs to that release, which
  would delete it on uninstall and conflict with the other operator
  modules); create it once:
  `norca namespace apply -description "Norca operators" norca-system`.
  Give rights in it to the operators of the cluster only: the job runs there
  with the ACL policy bound to it, the keys of its accounts are secrets of
  that namespace, and the tokens of the DNS zones are Variables of it by
  default.
- The binary on the nodes (`/usr/local/bin/norca-acme`, built in a
  norca-platform checkout with `go build -o norca-acme ./cmd/norca-acme`),
  or an image (`driver = "docker"`).
- Nodes without the raw_exec driver: the job keeps off nodes with it unless
  `allow_raw_exec_nodes = true`, and its default driver is `exec`; see
  [operator packs](../../README.md#operator-packs) (review finding JOG-19).
- **HTTP-01:** port 80 of the names must reach the edge router, and the
  [traefik](../traefik) module needs `acme_challenge = true` and the namespace
  of this job in `catalog_namespaces` (`["default", "norca-system"]`), with
  the policy its notes print that lets Traefik read the services of a
  namespace other than its own: its redirect to https then leaves
  `/.well-known/acme-challenge/` to this service.
- **DNS-01** (the only way for a wildcard): a provider of the
  [norca-provider](../norca-provider) module with a `dns` section for the
  zone, and its token in the Variable its `token_variable` names, in
  `zone_token_namespace` (the namespace of the job when empty):
  `norca var put -namespace norca-system providers/dns-eu token=...`.

## An issuer

```hcl
kind = "norca.io/CertificateIssuer"
name = "letsencrypt"
spec {
  external {
    controller = "norca-acme"
    config {
      directory = "https://acme-v02.api.letsencrypt.org/directory"
      email     = "ops@example.com"
      dns01 { zones = ["example.com"] }
    }
  }
}
```

| `config` | Meaning |
| --- | --- |
| `directory` | URL of the ACME directory (https). Use the staging directory of the certificate authority while trying. |
| `email` | Contact of the account. |
| `eab_secret` | Path of a secret below `secret_prefix` with the items `kid` and `hmac_key` (base64url), for a certificate authority that requires an external account binding. |
| `roots` | Root certificates (PEM) the chains lead to. Without it the chains are verified against the roots of the node the operator runs on. A private or test certificate authority needs it. |
| `http01` | `false` turns the HTTP-01 challenge off for the issuer. |
| `dns01 { zones, disabled }` | The DNS zones the issuer may use (empty: every registered zone), or no DNS-01 at all. |

Writing the issuer accepts the terms of service of its certificate
authority. The object is public, like every object: it holds paths of
secrets, never a secret. The status of the issuer shows the account, the
roots and a `problem` when the issuer cannot work; then it has no heartbeat
and the servers order nothing from it.

A certificate of the issuer, in a namespace that may ask for the names
(`norca.io/certificate-dns-suffixes` in the metadata of the namespace):

```hcl
kind      = "norca.io/Certificate"
namespace = "default"
name      = "web-tls"
spec {
  issuer      = "letsencrypt"
  dns_names   = ["example.com", "*.example.com"]
  secret_path = "certs/web"
}
```

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| the namespace of the release (`-namespace`) | `norca-system` in the install below | Namespace of the job and of its secrets; it must exist. The module has no variable for it. |
| `controller` | `norca-acme` | The name issuers name the operator by. |
| `secret_prefix` | `norca-acme/` | Where the operator keeps its secrets in its namespace: `accounts/<issuer>`, `issued/<issuer>/<serial>`. |
| `http01_enabled`, `http01_entrypoints` | `true`, `["web"]` | The HTTP-01 service and the Traefik entrypoints its router is on. |
| `http01_settle` | `""` | `-http01-settle`: the time after an instance became ready before the certificate authority is told to check an HTTP-01 challenge. Empty is the default of the operator, `30s`; `0s` turns the wait off. |
| `count` | `1` | Instances of the operator, 1 to 5. More than one run on different nodes, with leader election. |
| `leader_election` | `false` | Run with leader election. Always on with more than one instance; see [Several instances](#several-instances) for one instance. |
| `lease_namespace` | `""` | Namespace of the lease of the leader election; empty is the namespace of the job. |
| `zone_token_namespace`, `zone_token_path` | `""`, `providers/*` | The Variables with the tokens of the DNS zones; an empty namespace is the namespace of the job. |
| `zone_ttl`, `zone_allow_http`, `zone_ca_cert` | `3m`, `false`, `""` | When a zone counts as away; http endpoints (trials only); the CA of the providers. |
| `dns_resolver`, `dns_propagation_check`, `dns_propagation_timeout` | `""`, `true`, `5m` | The wait for the name servers of a zone before the certificate authority is told to look. |
| `acme_ca_cert` | `""` | The CA of the https certificate of the ACME directory (a private certificate authority). |
| `retry_base`, `retry_max`, `max_attempts` | `1m`, `2h`, `8` | Attempts of an order after a failure that passes. |
| `interval` | `5s` | Time between two passes. |
| `driver`, `binary`, `image` | `exec`, `/usr/local/bin/norca-acme` | How the task runs; `raw_exec` only with `allow_raw_exec_nodes`. |
| `allow_raw_exec_nodes` | `false` | Allow nodes with the raw_exec driver and `driver = "raw_exec"` (JOG-19). |
| `acl_policy_enabled` | `true` | Disable it on agents without ACLs. |

`examples/norca-acme/` has Let's Encrypt staging with a DNS zone, and a lab
with a test certificate authority.

## Several instances

By default the operator is **one instance without leader election**, as the
pack runs it. When its node is lost the instance is placed again, and it
continues the open orders from their status.

**`count = 2` (or more, up to 5) runs standbys**: the instances are placed
on different nodes and run with `-leader-election`. They share a lease, the
Variable `controller-lease/<controller>` (`controller-lease/norca-acme`) in
`lease_namespace`, the namespace of the job by default; only the instance
that holds it works on the orders, and it changes something at the
certificate authority, in a zone or in its secrets only while the lease
cannot have passed to another instance. A standby takes the lease over
about 20 seconds after the leader stopped renewing it, within a few seconds
when the leader was stopped in order. The standbys share no work.
`examples/several-instances.vars.hcl` is this way.

**`leader_election = true` with one instance** is for the case of review
finding CON-6e: an allocation that was lost (its node no longer reaches the
servers) may still run while its replacement starts, and without a lease
both work on the same orders.

**The HTTP-01 challenges must reach the instance that leads, and no
other** (review finding CON-6f). The answers are in its memory; a standby
answers a challenge with `503`. With leader election the service of the
job therefore has a second check:

```hcl
check {
  name      = "leading"
  type      = "http"
  path      = "/readyz"
  interval  = "5s"
  timeout   = "2s"
  on_update = "ignore"
}
```

`/readyz` answers `204` on the instance that leads and `503` on a standby,
so the standbys are unhealthy in the catalog. `on_update = "ignore"` keeps
the check out of the health of the deployment: a standby fails it for as
long as it is one, and its allocation would never become healthy. The check
on `/healthz`, which every instance passes, still counts for the
deployment.

What the cluster needs for it:

- **The clients that run Traefik return the healthy instances only**:

  ```hcl
  client {
    native_service_discovery {
      default_healthy_only = true
    }
  }
  ```

  It is `false` by default. Traefik reads the catalog through the task API
  of its allocation, and a lookup of a workload returns every instance of
  a service, the standbys too, unless its client has this setting. Without
  it Traefik sends challenges to the standbys, and those orders fail. The
  setting does not reach a lookup at an agent address (`nomad_address` of
  the [traefik](../traefik) module), which returns every instance: keep
  Traefik on the task API. Another edge router must ask for the healthy
  instances itself (the `healthy` parameter of the service API).
- **A settle time that covers the edge router** (review finding CON-6g).
  After a start or a change of the leader the edge router does not route
  to the new instance at once, so the operator answers a challenge at once
  but tells the certificate authority to check it only `-http01-settle`
  after the instance became ready. The default of the operator, 30
  seconds, covers the check above (5 seconds and its timeout of 2), the
  second the client takes to pass the result on, and the defaults of
  Traefik (the services read every 15 seconds, a change applied 2 seconds
  later). With a slower refresh of the edge router set `http01_settle`
  above the sum. A challenge the certificate authority was told to check
  before the leader changed cannot be held back: that order may fail once,
  and the servers place it again.
- **As many nodes the job may run on as instances** (`datacenters`,
  `node_pool`, no raw_exec driver, not made by the node scaling operator):
  the instances never share a node.
- **A norca-acme binary or image built from norca-platform of 2026-11-21
  or later**: an older one does not know `-leader-election`,
  `-http01-settle` or `/readyz`, and does not start with the flags.
- **The lease in the ACL policy.** The policy of the module grants `read`
  and `write` on the one path, in `lease_namespace`. With
  `acl_policy_enabled = false` the policy bound to the job by other means
  must grant it, or no instance ever leads and no order is fulfilled.

DNS-01 needs none of the routing: the instance that leads writes the
challenge records.

The lease is a Variable the operator writes, not a resource of the
release: uninstalling the release leaves it
(`norca var purge -namespace norca-system controller-lease/norca-acme`).

## Install

```shell
norca namespace apply -description "Norca operators" norca-system   # once
rigger install ./modules/norca-acme -name acme -namespace norca-system
norca object apply letsencrypt.hcl
norca object list norca.io/CertificateIssuer
```

## Limitations

- One instance works at a time: the answers of the HTTP-01 challenges are
  in the memory of the instance that placed the order, and further
  instances are standbys ([Several instances](#several-instances)). An
  order that is open when the instance is lost is continued by the next
  one.
- The TLS-ALPN-01 challenge is not supported.
- A revocation needs the certificate: the operator keeps the certificates
  it issued, below `secret_prefix`, until they expire. A certificate of
  another client of the same account cannot be revoked through it.
- Certificate authorities limit the rate of orders and of failed
  validations. Try an issuer against the staging directory first.

## Install

```shell
rigger install ./modules/norca-acme -name norca-acme -namespace norca-system
```

Outputs: `job`, `controller` and `notes`. The ACL policy is the resource `acme`; `acl_policy_enabled` leaves it out. `driver = "raw_exec"` without `allow_raw_exec_nodes = true` is refused by the rule `raw_exec` (the `fail` of the pack); `examples/raw-exec.vars.hcl` is the allowed way.

## From the pack

Converted from the pack `norca-acme` 0.2.0 with `rigger convert pack`; for the
defaults and every example it renders the jobs and other resources of the
pack (`scripts/compare-packs.sh norca-acme`). The job ID is `job_name`, as in the pack. The namespace and the region are
the release's.

The module is version 0.3.0: beyond the pack it has `count`, `leader_election`, `lease_namespace` and `http01_settle`, several instances with leader election, the lease in the ACL policy and the check on `/readyz` (review findings CON-6e, CON-6f, CON-6g), which `examples/several-instances.vars.hcl` shows and the comparison with the pack leaves out; with the defaults and the examples of the pack it renders what the pack renders.
