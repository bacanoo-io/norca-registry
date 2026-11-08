<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# norca-provider

The provider application of Norca, `norca-provider` of
[norca-platform](https://github.com/bacanoo-io/norca-platform), as one
release. One process serves the platforms its configuration names, each a
type of `norca-provider` (`hcloud`, `aws`, `gcp`, `digitalocean`, `vultr`,
`scaleway`, `nginx`, `tcpproxy`, `docker`, `mock`; `norca-provider types`
lists them with their parameters):

- the **node providers** of the node scaling operator
  ([nodescaler-operator](../nodescaler-operator)): a `norca.io/NodeProvider`
  object per provider with a `node` section, served at
  `<advertise_url>/providers/<name>`;
- the **load balancer classes** of the LoadBalancer operator
  ([loadbalancer-operator](../loadbalancer-operator)): a
  `norca.io/LoadBalancerClass` object per class, served at
  `<advertise_url>/classes/<class>`.

Both kinds of objects carry the same heartbeat (`status.heartbeat`) and are
removed when the provider stops (`deregister_on_exit`).

| Template | Resource |
| --- | --- |
| `provider.acl.hcl.tpl` | ACL policy bound to the job (`job_acl`): `read`, `write` and `write-status` on the `norca.io/NodeProvider` and `norca.io/LoadBalancerClass` objects (cluster-scoped, so in the namespace `"*"`), nothing else |
| `provider.nomad.tpl` | The job: one instance on a static port, never on a node the node scaling operator created, the configuration file rendered from the variables, the secrets of the job's Variable as environment variables, a service with an http check on `/healthz` |

## Before

- The binary on the nodes (`/usr/local/bin/norca-provider`, built in a
  norca-platform checkout with `go build -o norca-provider ./cmd/norca-provider`),
  or an image (`driver = "docker"`, the `Dockerfile` of norca-platform). The
  `docker` platform runs the docker CLI of its host: use `raw_exec` for it.
- The kinds: `NodeProvider` is registered by the core, `LoadBalancerClass`
  by the loadbalancer-operator pack (`class_kind_enabled`).
- The secrets in the job's Variable `nomad/jobs/<job_name>` (with
  `secrets = true`): every item becomes an environment variable of the task,
  for the `env:NAME` references of the configuration. The job reads its own
  Variable without a rule of the policy.
- The token of each provider twice: in the job's Variable for the provider
  (`"token": "env:PROVIDER_TOKEN"`), and in the Variable its `token_variable`
  names (item `token`) for the operators.

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `providers` | a mock class without a token | The `providers` array of the configuration of norca-provider, as JSON (see the README of norca-platform and its `providers.example.json`). |
| `port` | `8443` | Static port of the server; the operators call it, so open it in the firewall. |
| `advertise_url` | `http(s)://<task address>:<port>` | Base URL the operators reach the provider on. `${NAME}` refers to the environment of the task. |
| `heartbeat_interval` | `30s` | Period of the heartbeat of the registrations. |
| `secrets` | `false` | The items of `nomad/jobs/<job_name>` as environment variables of the task; the Variable must exist. |
| `tls_enabled` | `false` | https with the items `tls_cert` and `tls_key` of the job's Variable. The LoadBalancer operator calls http only with `class_allow_http`. |
| `deregister_on_exit` | `true` | Remove the registrations when the provider stops. |
| `driver`, `binary`, `image` | `raw_exec`, `/usr/local/bin/norca-provider` | How the task runs. |
| `acl_policy_enabled` | `true` | Disable it on agents without ACLs. |

`examples/norca-provider/` has a Hetzner Cloud setup on https and a lab with
the docker platform and a mock class.

## Install

```shell
norca var put nomad/jobs/norca-provider PROVIDER_TOKEN=... HCLOUD_TOKEN=...
norca var put providers/hetzner-eu token=...
norca pack run ./packs/norca-provider --name=provider -f examples/norca-provider/hetzner.hcl
norca object list norca.io/LoadBalancerClass
```

## Limitations

- One instance: the providers of a configuration are registered once, and a
  platform that keeps its load balancers in the process (`tcpproxy`) must
  not run twice. Split the providers over several releases (`job_name`) to
  run them on different nodes.
- The configuration is a JSON string: it is checked by `norca-provider` when
  the task starts (a wrong type, a missing parameter, a section the type does
  not implement), not by the pack.
