[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* region, namespace, datacenters and node_pool of a job. */ -]]
[[- define "nats.location" -]]
[[- $v := vars . ]]
[[- if ne $v.region "" ]]
  region      = [[ $v.region | quote ]]
[[- end ]]
[[- if ne $v.namespace "" ]]
  namespace   = [[ $v.namespace | quote ]]
[[- end ]]
[[- if $v.datacenters ]]
  datacenters = [[ $v.datacenters | toStringList ]]
[[- end ]]
[[- if ne $v.node_pool "" ]]
  node_pool   = [[ $v.node_pool | quote ]]
[[- end ]]
[[- end -]]

[[- /* A network port: static unless the number is 0, bound to host_network if set. */ -]]
[[- define "nats.port" -]]
    port [[ .label | quote ]] {
[[- if gt .number 0 ]]
      static = [[ .number ]]
[[- end ]]
[[- if ne .host_network "" ]]
      host_network = [[ .host_network | quote ]]
[[- end ]]
    }
[[- end -]]

[[- /* A JSON-free NATS string list: ["a", "b"] (toJson would escape > as \u003e,
which the NATS configuration parser rejects). */ -]]
[[- define "nats.list" -]]
[ [[ range $i, $s := . ]][[ if $i ]], [[ end ]][[ $s | quote ]][[ end ]] ]
[[- end -]]

[[- /* The permissions of a user entry (call with a users element, or a dict with
the same keys), indented for the accounts block. Nothing without permissions. */ -]]
[[- define "nats.permissions" -]]
[[- if or .publish_allow .publish_deny .subscribe_allow .subscribe_deny .allow_responses ]]
                  permissions: {
[[- if or .publish_allow .publish_deny ]]
                    publish: {
[[- if .publish_allow ]]
                      allow: [[ template "nats.list" .publish_allow ]]
[[- end ]]
[[- if .publish_deny ]]
                      deny: [[ template "nats.list" .publish_deny ]]
[[- end ]]
                    }
[[- end ]]
[[- if or .subscribe_allow .subscribe_deny ]]
                    subscribe: {
[[- if .subscribe_allow ]]
                      allow: [[ template "nats.list" .subscribe_allow ]]
[[- end ]]
[[- if .subscribe_deny ]]
                      deny: [[ template "nats.list" .subscribe_deny ]]
[[- end ]]
                    }
[[- end ]]
[[- if .allow_responses ]]
                    allow_responses: true
[[- end ]]
                  }
[[- end ]]
[[- end -]]

[[- /* auth_mode = "userpass": the accounts with their users, part of the server
configuration template of the task. The passwords are read from the secret store
when the template renders; a missing password item fails the template instead of
rendering an empty password (which NATS would accept without a password). */ -]]
[[- define "nats.userpass" -]]
[[- $v := vars . ]]
[[- /* The accounts in the order of their first user. */ -]]
[[- $accounts := list ]]
[[- range $u := $v.users ]]
[[- $a := $u.account | default $v.users_default_account ]]
[[- if not (has $a $accounts) ]][[ $accounts = append $accounts $a ]][[ end ]]
[[- end ]]
[[- if and $v.bridge_enabled (not (has $v.users_default_account $accounts)) ]][[ $accounts = append $accounts $v.users_default_account ]][[ end ]]

          # auth_mode = "userpass": every account has its own subjects[[ if $v.jetstream_enabled ]] and
          # JetStream streams[[ end ]]. The passwords (plain or bcrypt) come from the secret
          # store ([[ $v.users_secret_prefix ]]/<user>); a new version is applied with a reload.
          accounts {
[[- range $a := $accounts ]]
            [[ $a | quote ]]: {
[[- if and $v.jetstream_enabled (ne $a $v.system_account) ]]
              jetstream: enabled
[[- end ]]
              users: [
[[- range $u := $v.users ]]
[[- if eq ($u.account | default $v.users_default_account) $a ]]
[[- $path := printf "%s/%s" $v.users_secret_prefix $u.name ]]
                {
                  user: [[ $u.name | quote ]]
                  password: "{{ with (nomadSecret "[[ $path ]]").password }}{{ . | replaceAll "\\" "\\\\" | replaceAll "\"" "\\\"" }}{{ else }}{{ sprig_fail "the secret [[ $path ]] has no item password" }}{{ end }}"
[[- template "nats.permissions" $u ]]
                }
[[- end ]]
[[- end ]]
[[- if and $v.bridge_enabled (eq $a $v.users_default_account) ]]
                # The event stream bridge (job [[ $v.bridge_job_name ]]): publishes the events
                # and looks up or creates its stream; replies come to its inboxes.
                {
                  nkey: [[ $v.bridge_nkey | quote ]]
[[- template "nats.permissions" (dict "publish_allow" (list (printf "%s.>" $v.bridge_subject_prefix) "$JS.API.STREAM.INFO.*" "$JS.API.STREAM.CREATE.*") "subscribe_allow" (list "_INBOX.>")) ]]
                }
[[- end ]]
              ]
            }
[[- end ]]
          }
[[- if has $v.system_account $accounts ]]
          system_account: [[ $v.system_account | quote ]]
[[- end ]]
[[- end -]]

[[- /* Validation of the variables. */ -]]
[[- define "nats.validate" -]]
[[- $v := vars . -]]
[[- if not (has $v.driver (list "docker" "raw_exec" "exec")) -]]
[[- fail (printf "driver must be docker, raw_exec or exec, got %q" $v.driver) -]]
[[- end -]]
[[- if not (has $v.storage (list "ephemeral_disk" "host_volume" "path")) -]]
[[- fail (printf "storage must be ephemeral_disk, host_volume or path, got %q" $v.storage) -]]
[[- end -]]
[[- if and (eq $v.storage "host_volume") (eq $v.driver "raw_exec") -]]
[[- fail "raw_exec does not support volume mounts: use storage = \"path\" with store_path, or the docker/exec driver" -]]
[[- end -]]
[[- if and (eq $v.storage "path") (eq $v.store_path "") -]]
[[- fail "storage = \"path\" needs store_path" -]]
[[- end -]]
[[- if not (has $v.auth_mode (list "none" "token" "nkey" "config" "userpass")) -]]
[[- fail (printf "auth_mode must be none, token, nkey, config or userpass, got %q" $v.auth_mode) -]]
[[- end -]]
[[- if eq $v.auth_mode "userpass" -]]
[[- if and (not $v.users) (not $v.bridge_enabled) -]]
[[- fail "auth_mode = \"userpass\" needs at least one entry in users (without users nobody could connect)" -]]
[[- end -]]
[[- $names := list -]]
[[- range $u := $v.users -]]
[[- if has $u.name $names ]][[ fail (printf "users: the name %q is used twice" $u.name) ]][[ end -]]
[[- $names = append $names $u.name -]]
[[- end -]]
[[- if $v.bridge_enabled -]]
[[- if eq $v.bridge_nkey "" ]][[ fail "auth_mode = \"userpass\" with bridge_enabled needs bridge_nkey (the public NKey of the bridge's user)" ]][[ end -]]
[[- if has $v.bridge_job_name $names ]][[ fail (printf "users: %q is the secret of the bridge (<users_secret_prefix>/<bridge_job_name>); use another name" $v.bridge_job_name) ]][[ end -]]
[[- if eq $v.users_default_account $v.system_account ]][[ fail "users_default_account must not be the system account (the bridge's user is in users_default_account)" ]][[ end -]]
[[- end -]]
[[- else if $v.users -]]
[[- fail "users needs auth_mode = \"userpass\"" -]]
[[- end -]]
[[- if lt $v.count 1 -]]
[[- fail "count must be at least 1" -]]
[[- end -]]
[[- if and $v.remote_gateways (not $v.gateway_enabled) -]]
[[- fail "remote_gateways needs gateway_enabled = true" -]]
[[- end -]]
[[- if $v.bridge_enabled -]]
[[- if not (has $v.bridge_driver (list "docker" "raw_exec" "exec")) -]]
[[- fail (printf "bridge_driver must be docker, raw_exec or exec, got %q" $v.bridge_driver) -]]
[[- end -]]
[[- if and (eq $v.bridge_driver "docker") (eq $v.bridge_image "") -]]
[[- fail "bridge_driver = \"docker\" needs bridge_image" -]]
[[- end -]]
[[- end -]]
[[- end -]]
