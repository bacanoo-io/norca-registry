<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# traefik

[Traefik Proxy](https://traefik.io/traefik/) (MIT) as the edge router of a
Norca region: the entrypoints are the ports open to the outside, the routes
come from the tags of the services in Norca's native catalog and from static
configuration, the certificates from the built-in secret store. The official
image is used unchanged; the pack ships no Traefik code.

Needs Norca 0.3.0 or later (the entrypoint table of the install form and the
`item_options` of the variables).

## What it deploys

**Job `traefik`** (name: `job_name`), group `traefik`, task `traefik` (docker):

- `job_type = "service"`: `count` instances (default 2), one per node
  (`distinct_hosts`); `"system"`: one on every node of the `node_pool` and
  `datacenters`, e.g. the edge nodes behind DNS round robin or an external
  load balancer;
- a static port per entrypoint, on the node itself (`network_mode = "host"`,
  the default: client addresses stay visible, UDP works) or mapped into the
  allocation's network (`"bridge"`), optionally on a client host network
  (`host_network`, e.g. the public interface);
- the admin entrypoint `traefik` on `admin_port` (8080) with `/ping`, the
  health check of the service `<job>`, and optionally the dashboard
  (`dashboard`) and Prometheus `/metrics` (`metrics`). Keep it closed to the
  outside;
- a service `<job>-<entrypoint>` per entrypoint (tags `entrypoint` and the
  protocol), for an external load balancer or DNS.

## Entrypoints

The entrypoints are a table on the **Entrypoints** tab of the install form
(name, port, protocol, redirect), or the `entrypoints` variable:

| protocol | Use |
| --- | --- |
| `http` | HTTP/1.1, WebSocket, gRPC without TLS (h2c) |
| `https` | the same over TLS with the certificates of the TLS tab; HTTP/2 and gRPC by ALPN |
| `tcp` | raw TCP: databases, message brokers, TLS passthrough by SNI |
| `udp` | UDP: DNS, syslog, game servers |

`redirect_to` on an `http` entrypoint names an `https` entrypoint that all its
requests are redirected to (301). The default is `web` (80, redirected) and
`websecure` (443). Names are letters, digits, `-` and `_`; the name `traefik`
and the `admin_port` are taken; a port is used once (TCP and UDP alike, as
Nomad reserves both).

```hcl
entrypoints = [
  { name = "web", port = 80, protocol = "http", redirect_to = "websecure" },
  { name = "websecure", port = 443, protocol = "https" },
  { name = "postgres", port = 5432, protocol = "tcp" },
]
```

## Certificates from the secret store

Every secret of `tls_certificates` holds one certificate: the item `cert`
(PEM, with the chain) and the item `key` (PEM) (`tls_cert_item`,
`tls_key_item`), in the namespace of the job. Traefik picks the certificate
by the SNI name of a connection; `tls_default_certificate` (default: the
first one) serves the connections without a match. Secret paths take
letters, digits, `-`, `_`, `~` and `/` (no dots: `traefik/certs/example-com`).
The job grants its task read access to these secrets (`secret_access`), so
whoever installs the pack needs `read-secret` on them.

```shell
norca secret put traefik/certs/example-com cert=@fullchain.pem key=@privkey.pem
```

```hcl
tls_certificates = ["traefik/certs/example-com", "traefik/certs/example-org"]
tls_min_version  = "VersionTLS12"
```

The certificates are rendered as PEM content into the dynamic configuration
`secrets/dynamic/tls.yml` of the allocation; Traefik watches the directory, so
a renewed certificate (`norca secret put` again) is applied without a restart.
A missing secret fails the template: the allocation does not start with a
wrong certificate. Without certificates the `https` entrypoints serve
Traefik's self-signed default certificate.

## Routing

**Services of the catalog** (`catalog_enabled`, the Nomad provider of Traefik
on Norca's native catalog): a service of the `catalog_namespaces` is routed
when it has the tag `traefik.enable=true` (or every service with
`exposed_by_default`), with the usual Traefik tags:

```hcl
service {
  name     = "app"
  port     = "http"
  provider = "nomad"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.app.rule=Host(`app.example.com`)",
    "traefik.http.routers.app.entrypoints=websecure",
  ]
}
```

Only healthy instances are routed. Traefik reads the catalog through the task
API socket of its allocation with its workload identity, which can read the
services of its own namespace; for the other namespaces bind a policy with
`read-job` to the job (the output of the pack prints it). `nomad_address`
points it at an agent address instead.

**Static configuration** (`dynamic_config`, the **Routing** tab): routers,
services and middlewares in Traefik's dynamic configuration (YAML of the file
provider), for backends outside the catalog. It is applied without a restart
and is not interpolated by the job's templates.

## Examples

`examples/traefik/` of the registry, each with the static configuration of a
common case:

| File | Case |
| --- | --- |
| `web.hcl` | a website over HTTPS: 80 redirects to 443, a certificate of the secret store, two backends with an active health check, security headers, compression |
| `websocket.hcl` | WebSocket (`wss://`): the Upgrade passes through by itself; a sticky cookie keeps a client on its backend |
| `grpc.hcl` | gRPC: TLS (HTTP/2 by ALPN) at Traefik, plaintext HTTP/2 (`h2c://`) to the backends, gRPC health checks |
| `tcp.hcl` | raw TCP: PostgreSQL on its own entrypoint, TLS passthrough by SNI on 443, a UDP entrypoint (DNS) |

```shell
norca secret put traefik/certs/example-com cert=@fullchain.pem key=@privkey.pem
norca pack run traefik --registry=norca --name=traefik -f examples/traefik/web.hcl
```

## Variables

| Variable | Default | |
|---|---|---|
| `job_type`, `count` | `service`, `2` | `system`: one per node of the node pool |
| `datacenters`, `node_pool`, `constraints` | `["*"]`, `""`, `[]` | placement (the edge nodes) |
| `image`, `image_digest` | `docker.io/library/traefik:v3.7.16`, `""` | the official image |
| `entrypoints` | `web` (80 → 443), `websecure` (443) | name, port, protocol, redirect_to |
| `network_mode`, `host_network` | `host`, `""` | where the ports are bound |
| `admin_port`, `dashboard`, `metrics` | `8080`, `false`, `false` | the admin entrypoint |
| `tls_certificates`, `tls_default_certificate` | `[]`, `""` | secrets with the items cert and key |
| `tls_min_version` | `VersionTLS12` | |
| `catalog_enabled`, `catalog_namespaces`, `exposed_by_default` | `true`, `["default"]`, `false` | routing by service tags |
| `dynamic_config` | `""` | static routes (YAML) |
| `log_level`, `access_log` | `INFO`, `false` | |
| `resources` | 200 MHz, 256 MB | |
