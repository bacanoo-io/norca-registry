[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $ns := "" ]][[ if ne $v.namespace "" ]][[ $ns = printf " -namespace %s" $v.namespace ]][[ end ]]
PostgreSQL "[[ $job ]]": one server, port [[ $v.port ]] on its node, service [[ $job ]] in the native catalog[[ if ne $v.tls_mode "none" ]], TLS ([[ $v.tls_mode ]][[ if $v.tls_required ]], required[[ end ]])[[ end ]]; data on the host volume [[ $v.host_volume ]].

Secrets it reads (create them before the first start):
  norca secret put[[ $ns ]] [[ $v.superuser_secret_path ]] password=-
[[- range $d := $v.databases ]]
  norca secret put[[ $ns ]] [[ $d.secret_path ]] password=-      # role [[ $d.user ]], database [[ $d.name ]]
[[- end ]]
[[- if $v.monitoring_enabled ]]
  norca secret put[[ $ns ]] [[ $v.monitoring_secret_path ]] password=-      # role [[ $v.monitoring_user ]] (pg_monitor)
[[- end ]]
[[- if eq $v.tls_mode "secret" ]]
  norca secret put[[ $ns ]] [[ $v.tls_secret_path ]] cert=@postgres.pem key=@postgres-key.pem
[[- end ]]
[[- if $v.dump_enabled ]]
  norca secret put[[ $ns ]] [[ $v.dump_storage_secret_path ]] access_key=<access key> secret_key=-
[[- end ]]

Checks:
  norca job status[[ $ns ]] [[ $job ]]
  norca service info[[ $ns ]] -verbose [[ $job ]]
[[- if or $v.databases $v.monitoring_enabled ]]
  norca alloc logs[[ $ns ]] -task setup <alloc ID>     # the roles and databases
[[- end ]]

Clients in the namespace find the server with nomadService "[[ $job ]]" in a template
(or [[ $job ]].service.<namespace>.nomad through the built-in DNS).
[[- if $v.dump_enabled ]]

Dumps: periodic job [[ $job ]]-dump ([[ $v.dump_cron ]] UTC) into [[ $v.dump_bucket ]]/[[ $v.dump_prefix ]].
[[- else ]]

No dumps: Norca's backups don't cover the data of PostgreSQL. Set dump_enabled (or back up otherwise).
[[- end ]]
