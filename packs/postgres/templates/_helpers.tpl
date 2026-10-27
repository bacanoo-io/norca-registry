[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* Checks the variables the schema can't express. */ -]]
[[- define "postgres.validate" -]]
[[- $v := vars . -]]
[[- $names := list ]]
[[- range $d := $v.databases ]]
[[- if has $d.name $names ]][[ fail (printf "database %q is listed twice" $d.name) ]][[ end ]]
[[- if or (eq $d.user $v.superuser) (and $v.monitoring_enabled (eq $d.user $v.monitoring_user)) ]][[ fail (printf "the owner of database %q can't be the superuser or the monitoring role" $d.name) ]][[ end ]]
[[- $names = append $names $d.name ]]
[[- end ]]
[[- if and $v.monitoring_enabled (eq $v.monitoring_user $v.superuser) ]][[ fail "monitoring_user must differ from superuser" ]][[ end ]]
[[- if and $v.tls_required (eq $v.tls_mode "none") ]][[ fail "tls_required needs tls_mode = \"mtls\" or \"secret\"" ]][[ end ]]
[[- end -]]

[[- /* region, namespace, datacenters, node_pool and the extra constraints of a job. */ -]]
[[- define "postgres.location" -]]
[[- $v := vars . ]]
[[- if ne $v.region "" ]]
  region      = [[ $v.region | quote ]]
[[- end ]]
[[- if ne $v.namespace "" ]]
  namespace   = [[ $v.namespace | quote ]]
[[- end ]]
  datacenters = [[ $v.datacenters | toStringList ]]
[[- if ne $v.node_pool "" ]]
  node_pool   = [[ $v.node_pool | quote ]]
[[- end ]]
[[- range $c := $v.constraints ]]

  constraint {
    attribute = [[ $c.attribute | quote ]]
    operator  = [[ $c.operator | quote ]]
[[- if ne $c.value "" ]]
    value     = [[ $c.value | quote ]]
[[- end ]]
  }
[[- end ]]
[[- end -]]

[[- /* The password of the superuser as PGPASSWORD (setup and dump tasks). */ -]]
[[- define "postgres.superuser_env" -]]
[[- $v := vars . ]]

      secret "superuser" {
        path = [[ $v.superuser_secret_path | quote ]]

        env {
          PGPASSWORD = "password"
        }
      }
[[- end -]]
