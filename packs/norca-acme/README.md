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
| `acme.acl.hcl.tpl` | ACL policy bound to the job (`job_acl`): `read` and `write-status` on `norca.io/CertificateIssuer` and `norca.io/CertificateOrder`, `read` on `norca.io/DNSZone` (cluster-scoped, so in the namespace `"*"`), the secrets below `secret_prefix`, the token Variables of the DNS zones |
| `acme.nomad.tpl` | The job: one instance, never on a node the node scaling operator created; a service that answers the HTTP-01 challenge, with the router of the Traefik pack as catalog tags |

## Before

- The binary on the nodes (`/usr/local/bin/norca-acme`, built in a
  norca-platform checkout with `go build -o norca-acme ./cmd/norca-acme`),
  or an image (`driver = "docker"`).
- **HTTP-01:** port 80 of the names must reach the edge router, and the
  [traefik](../traefik) pack needs `acme_challenge = true` and the namespace
  of this job in `catalog_namespaces`: its redirect to https then leaves
  `/.well-known/acme-challenge/` to this service.
- **DNS-01** (the only way for a wildcard): a provider of the
  [norca-provider](../norca-provider) pack with a `dns` section for the
  zone, and its token in the Variable its `token_variable` names.

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
| `controller` | `norca-acme` | The name issuers name the operator by. |
| `secret_prefix` | `norca-acme/` | Where the operator keeps its secrets in its namespace: `accounts/<issuer>`, `issued/<issuer>/<serial>`. |
| `http01_enabled`, `http01_entrypoints` | `true`, `["web"]` | The HTTP-01 service and the Traefik entrypoints its router is on. |
| `zone_token_namespace`, `zone_token_path` | `default`, `providers/*` | The Variables with the tokens of the DNS zones. |
| `zone_ttl`, `zone_allow_http`, `zone_ca_cert` | `3m`, `false`, `""` | When a zone counts as away; http endpoints (trials only); the CA of the providers. |
| `dns_resolver`, `dns_propagation_check`, `dns_propagation_timeout` | `""`, `true`, `5m` | The wait for the name servers of a zone before the certificate authority is told to look. |
| `acme_ca_cert` | `""` | The CA of the https certificate of the ACME directory (a private certificate authority). |
| `retry_base`, `retry_max`, `max_attempts` | `1m`, `2h`, `8` | Attempts of an order after a failure that passes. |
| `interval` | `5s` | Time between two passes. |
| `driver`, `binary`, `image` | `raw_exec`, `/usr/local/bin/norca-acme` | How the task runs. |
| `acl_policy_enabled` | `true` | Disable it on agents without ACLs. |

`examples/norca-acme/` has Let's Encrypt staging with a DNS zone, and a lab
with a test certificate authority.

## Install

```shell
norca pack run ./packs/norca-acme --name=acme
norca object apply letsencrypt.hcl
norca object list norca.io/CertificateIssuer
```

## Limitations

- One instance: the answers of the HTTP-01 challenges are in the memory of
  the instance that placed the order. An order that is open when the
  instance is lost is continued by the next one.
- The TLS-ALPN-01 challenge is not supported.
- A revocation needs the certificate: the operator keeps the certificates
  it issued, below `secret_prefix`, until they expire. A certificate of
  another client of the same account cannot be revoked through it.
- Certificate authorities limit the rate of orders and of failed
  validations. Try an issuer against the staging directory first.
