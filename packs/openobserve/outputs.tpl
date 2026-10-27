[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $ns := "" ]][[ if ne $v.namespace "" ]][[ $ns = printf " -namespace %s" $v.namespace ]][[ end ]]
[[- $nsName := $v.namespace ]][[ if eq $nsName "" ]][[ $nsName = "<namespace>" ]][[ end ]]
[[- $scheme := "https" ]][[ if eq $v.tls_mode "none" ]][[ $scheme = "http" ]][[ end ]]
[[- $cluster := eq $v.mode "cluster" ]]
OpenObserve "[[ $job ]]" ([[ if $cluster ]]cluster: [[ range $i, $r := list "router" "ingester" "querier" "compactor" "alertmanager" ]][[ if $i ]], [[ end ]][[ (get $v.roles $r).count ]] [[ $r ]][[ end ]][[ else ]]single instance on the host volume [[ $v.host_volume ]][[ end ]]), TLS [[ $v.tls_mode ]].

UI and API: [[ $scheme ]]://<node address of [[ if $cluster ]]a router[[ else ]]the instance[[ end ]]>:[[ $v.http_port ]]/
[[- if eq $v.tls_mode "mtls" ]]
  or [[ $scheme ]]://[[ $job ]].service.[[ $nsName ]].nomad:[[ $v.http_port ]]/ through the built-in DNS. The certificate is
  Norca's workload certificate for that name: browsers trust it once the CA of the
  region is imported (norca operator api /v1/mtls/roots), see the README.
  The client restarts an OpenObserve task after its certificate is renewed or
  the CA rotates (mtls change_mode = "restart"): a short interruption of that instance.
[[- end ]]
Log in as [[ $v.root_email ]] with the password of the secret [[ $v.root_secret_path ]].
OTLP: [[ $scheme ]]://.../api/[[ $v.ingest_organization ]]/v1/{logs,metrics,traces} (HTTP), port [[ $v.grpc_port ]] (gRPC).

Secrets it reads (create them before the first start):
  norca secret put[[ $ns ]] [[ $v.root_secret_path ]] password=-      # 8+ chars, upper and lower case, digit, special character
[[- if $cluster ]]
[[- if ne $v.postgres_dsn_secret_path "" ]]
  norca secret put[[ $ns ]] [[ $v.postgres_dsn_secret_path ]] dsn=-
[[- else ]]
  norca secret put[[ $ns ]] [[ $v.postgres_secret_path ]] password=-      # the postgres pack: databases = [{name = "[[ $v.postgres_database ]]", user = "[[ $v.postgres_user ]]", secret_path = "[[ $v.postgres_secret_path ]]"}]
[[- end ]]
  norca secret put[[ $ns ]] [[ $v.s3_secret_path ]] access_key=<access key> secret_key=-
[[- if ne $v.nats_secret_path "" ]]
  norca secret put[[ $ns ]] [[ $v.nats_secret_path ]] username=openobserve password=-      # its user of the nats pack (auth_mode = "userpass"), see the README
[[- end ]]
[[- end ]]
[[- if eq $v.tls_mode "secret" ]]
  norca secret put[[ $ns ]] [[ $v.tls_secret_path ]] cert=@cert.pem key=@key.pem ca=@ca.pem
[[- end ]]
[[- if $v.bootstrap_enabled ]]

The bootstrap task stores the ingest credentials of [[ $v.ingest_service_account ]] in [[ $v.ingest_secret_path ]]:
  norca alloc logs[[ $ns ]] -task bootstrap <alloc ID>     # "ingest credentials ... stored"
[[- if not $v.acl_policy_enabled ]]
Without the ACL policy of the pack, writing the secret needs an agent without ACLs.
[[- end ]]
[[- end ]]

Checks:
  norca job status[[ $ns ]] [[ $job ]]
  norca service info[[ $ns ]] -verbose [[ $job ]]

Next: the otel-collector pack in the same namespace ships the metrics of every
node and receives OTLP from applications:
  norca pack run otel-collector --registry=norca[[ if ne $v.namespace "" ]] --namespace=[[ $v.namespace ]][[ end ]] -f otel-collector.hcl
[[- if ne $v.tls_restart_interval "" ]]

Note: tls_restart_interval is deprecated and ignored since pack version 0.2.0
(there are no periodic restarts any more); remove it from the variable file.
[[- end ]]
