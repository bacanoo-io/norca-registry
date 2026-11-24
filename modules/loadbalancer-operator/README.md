<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# loadbalancer-operator

The LoadBalancer operator of Norca (`norca-loadbalancer`,
[`loadbalancer/operator`](https://github.com/bacanoo-io/norca-platform/tree/main/loadbalancer/operator)
in the norca-platform repository) packaged as an **operator module**: one
release installs, upgrades, rolls back and uninstalls everything the operator
needs, in the fixed order of the extended module format.

| Template | Resource |
| --- | --- |
| `controller.acl.hcl.tpl` | ACL policy bound to the controller job (`job_acl`): in the watched namespace (`watch_namespace`) jobs, the proxy jobs' Variables and the `norca.io/LoadBalancer` objects (status, events, finalizers); the leases in the namespace of the job; read of the `norca.io/LoadBalancerClass` objects and of the tokens of the classes (`class_token_path`), and node read (an instance on a node marked `norca.lb.leaving` is not a target) |
| `loadbalancer.kind.hcl.tpl` | Object kind `norca.io/LoadBalancer`: JSON Schema with defaults, a CEL transition rule, display columns, optional webhooks, limits; optional (`loadbalancer_kind_enabled`) |
| `loadbalancerclass.kind.hcl.tpl` | Object kind `norca.io/LoadBalancerClass`: the classes the providers register, with their heartbeat (`status.heartbeat`); optional (`class_kind_enabled`) |
| `service-marks.admission.hcl.tpl` | Admission policy: services marked with `norca_lb_port` must name a valid port (optional) |
| `controller.nomad.tpl` | The controller job (two instances with leader election) and the optional webhook task |

The values are checked against the `validation` blocks and rules of
[`variables.hcl`](variables.hcl) before rendering; the servers check the
`validation` blocks again.

## Install

Build the binary in a norca-platform checkout and install it on the nodes (or
build an image with it), create the namespace of the operators once (the
module expects it and does not create it, see [Namespaces](#namespaces)), then
install the module from the registry or from a checkout of the registry:

```shell
cd norca-platform && go build -o /usr/local/bin/norca-loadbalancer ./cmd/norca-loadbalancer
norca namespace apply -description "Norca operators" norca-system
norca module plan ./modules/loadbalancer-operator
norca module run  ./modules/loadbalancer-operator --name=lb
norca module status lb
```

On an agent without ACLs (a dev agent), policies can't be written: add
`--var=acl_policy_enabled=false`.

The controller keeps off nodes with the raw_exec driver unless
`allow_raw_exec_nodes = true`, and its default driver is `exec`: see
[operator packs](../../README.md#operator-packs) (review finding JOG-19).
The proxy jobs it creates use `exec` by default too (`proxy_driver`), so a
cluster whose nodes run without raw_exec needs no change for them.
A dev agent usually enables raw_exec: add `-var allow_raw_exec_nodes=true`
there. `driver = "raw_exec"` without it is refused by the rule `raw_exec`
(the `fail` of the pack); `examples/raw-exec.vars.hcl` is the allowed way.

With a management token, the release can register the kind and bind the ACL
policy at once. A token with less rights needs `operator` write (the kind),
`acl` write (the policy) and `admission` write (the admission policy):
applying a release grants no extra permissions.

## Namespaces

The controller job runs in **the namespace of the release (`-namespace`),
`norca-system` for the operator modules of this registry**, an operations
namespace they share. It must exist before the install, and no module
creates it: a namespace that a release installs belongs to that release,
which would delete it on uninstall and conflict with the other operator
modules. Create it once, by hand or with the tooling of the cluster:

```shell
norca namespace apply -description "Norca operators" norca-system
```

Give rights in `norca-system` to the operators of the cluster only: the
controller job runs there with the ACL policy bound to it, and the tokens of
the classes are Variables of that namespace by default.

**`watch_namespace` names the namespace of the LoadBalancer objects apart
from the namespace of the job**: a namespace (`default` by default), or `*`
for every namespace. Empty is the namespace of the job.

```shell
rigger install ./modules/loadbalancer-operator -name lb -namespace norca-system \
  -var 'watch_namespace=*'
```

A controller job inside the namespace of a team would count against the
quota of the team and keep the namespace from being deleted. Norca refuses a
change of a job with ACL policies bound to it unless the token holds those
policies or is a management token, so a team token with `submit-job` can't
make the job run something else under its policy; a token without those
policies can't run commands in its allocations either (`alloc exec`). The
operations namespace keeps the job and the token Variables out of the
teams' reach altogether.

- The ACL policy gives the controller, in every watched namespace, what it
  needs there: `list-jobs`, `read-job` and `submit-job` (it registers the
  proxy jobs `lb-*` in the namespace of their load balancer), the Variables
  `nomad/jobs/lb-*` and the `norca.io/LoadBalancer` objects. With `*` that
  is every namespace of the cluster.
- The leader election leases stay in the namespace of the job
  (`-lease-namespace`).
- The admission policy for service marks follows the watched namespace.
- A second release for another namespace or region sets
  `loadbalancer_kind_enabled=false` and `class_kind_enabled=false`: the
  kinds belong to the release that installed them first.

## Providers

Load balancers of other classes than the built-in `nomad` one come from
providers: applications that register a `norca.io/LoadBalancerClass` object
per class and keep a heartbeat in it. `norca-provider` (the
[`norca-provider`](../norca-provider) module) is one. The controller calls a
class at its registered endpoint with the token of the Variable the class
names (item `token`, in `class_token_namespace`, which is the namespace of
the job when empty; the policy lets it read `class_token_path`):

```shell
norca var put -namespace norca-system providers/hetzner-eu token=...
```

A class whose heartbeat is older than `class_ttl` is
reported as `ProviderUnavailable`. Providers serve https; for a certificate
of a private CA give the CA in `class_ca_cert`, and `class_allow_http`
accepts http endpoints in a lab.

## Webhooks

`--var=webhook_enabled=true --var=webhook_url=https://<address>:8443` adds a
webhook task to the controller job and registers two webhooks in the kind:

- `default` fills in the class of the region (`default_class`) when a spec names none (the
  schema's static default `nomad` is left out then);
- `validate` rejects classes no provider of the region implements
  (`--var='classes=["nomad","aws-nlb"]'`) and class changes.

The servers call webhooks over https only. Put the certificate and key into
the job's Variable and the CA into `webhook_ca_cert`:

```shell
norca var put -namespace norca-system nomad/jobs/loadbalancer-controller webhook_cert=@lb.pem webhook_key=@lb-key.pem
norca module upgrade ./modules/loadbalancer-operator --name=lb --var=webhook_enabled=true \
  --var=webhook_url=https://lb-webhook.internal:8443 --var-file=ca.hcl
```

Webhooks of a kind written with a management token are approved at once;
otherwise an administrator approves them (`norca object-kind webhook approve
norca.io/LoadBalancer validate`). Any change of a webhook's configuration
needs a new approval. With `webhook_failure_policy = "fail"` (the default),
writes fail while the webhook is unreachable or unapproved.

## Limits

The kind carries the server-side load management of its objects:
`write_rate` (all identities), `identity_write_rate` (each token or workload
identity, so a misbehaving controller doesn't use up the budget of users),
`max_objects_per_namespace` and `max_watches_per_identity`. Writes over a
limit get `429 Too Many Requests`; the controller SDK backs off.

## Uninstall

```shell
norca module uninstall lb
```

deletes the job, the admission policy, the kinds and the policy in reverse
order. The kind can only be deleted when no LoadBalancer objects are left:
delete them first (the controller removes their load balancers through the
finalizer).

## Install

```shell
rigger install ./modules/loadbalancer-operator -name loadbalancer -namespace norca-system
```

Outputs: `job`, `watch_namespace` and `notes`. The kinds are the resources `load-balancer` and `load-balancer-class`, the ACL policy `controller`, the admission policy `service-marks`. The rules of the ACL policy are built line by line (`locals.hcl`), so they are the text the pack wrote for every placement of the watched namespace, the job and the tokens.

## From the pack

Converted from the pack `loadbalancer-operator` 0.4.0 with `rigger convert pack`; for the
defaults and every example it renders the jobs and other resources of the
pack (`scripts/compare-packs.sh loadbalancer-operator`). The job ID is `job_name`, as in the pack. The namespace and the region are
the release's.

The module is version 0.5.0 and has nothing the pack has not: after the conversion the pack changed defaults without a new version (`driver` and `proxy_driver` are `exec`, the tokens of the classes are in the namespace of the job, `norca-system`), the module follows them, and by the rule of the registry a changed default raises the minor version.
