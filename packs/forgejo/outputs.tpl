[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $ns := "" ]][[ if ne $v.namespace "" ]][[ $ns = printf " -namespace %s" $v.namespace ]][[ end ]]
[[- $scheme := "http" ]][[ if $v.https_enabled ]][[ $scheme = "https" ]][[ end ]]
[[- $port := int $v.http_port ]]
[[- $registry := $v.domain ]][[ if not (or (and $v.https_enabled (eq $port 443)) (and (not $v.https_enabled) (eq $port 80))) ]][[ $registry = printf "%s:%d" $v.domain $port ]][[ end ]]
Forgejo "[[ $job ]]": [[ if ne $v.root_url "" ]][[ $v.root_url ]][[ else ]][[ $scheme ]]://[[ $registry ]]/[[ end ]][[ if $v.ssh_enabled ]], SSH on port [[ $v.ssh_port ]][[ end ]]; SQLite and the repositories on the host volume [[ $v.host_volume ]][[ if $v.storage_enabled ]], objects in the bucket [[ $v.storage_bucket ]][[ end ]].

Secrets it reads (create them before the first start):
  norca secret put[[ $ns ]] [[ $v.keys_secret_path ]] secret_key=@secret_key internal_token=@internal_token jwt_secret=@jwt_secret lfs_jwt_secret=@lfs_jwt_secret
[[- if $v.admin_enabled ]]
  norca secret put[[ $ns ]] [[ $v.admin_secret_path ]] password=-
[[- end ]]
[[- if $v.storage_enabled ]]
  norca secret put[[ $ns ]] [[ $v.storage_secret_path ]] access_key=<access key> secret_key=-
[[- end ]]
[[- if $v.https_enabled ]]
  norca secret put[[ $ns ]] [[ $v.tls_secret_path ]] cert=@forgejo.pem key=@forgejo-key.pem
[[- end ]]
[[- if and $v.metrics_enabled (ne $v.metrics_token_secret_path "") ]]
  openssl rand -hex 32 | norca secret put[[ $ns ]] [[ $v.metrics_token_secret_path ]] token=-
[[- end ]]

Checks:
  norca job status[[ $ns ]] [[ $job ]]
  norca service info[[ $ns ]] -verbose [[ $job ]]
[[- if $v.admin_enabled ]]
  norca alloc logs[[ $ns ]] -task create-admin <alloc ID>    # "admin [[ $v.admin_username ]] created"
[[- end ]]

Container images: [[ $registry ]]/<owner>/<image>:<tag>
  docker login [[ $registry ]]
  docker push [[ $registry ]]/<owner>/<image>:<tag>
[[- if not $v.https_enabled ]]
Docker requires HTTPS for a registry on another host: set https_enabled, or put a
TLS-terminating proxy in front of Forgejo (root_url).
[[- end ]]

Next: a pull-only user and token for the nodes, the Docker auth file on every
client (plugin "docker" { config { auth { config = "/etc/norca/docker-auth.json" } } }),
see the README of the pack.
[[- if $v.dump_enabled ]]

Dumps: periodic job [[ $job ]]-dump ([[ $v.dump_cron ]] UTC) into [[ $v.dump_bucket ]]/[[ $v.dump_prefix ]].
[[- end ]]
