[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]

[[- /* Checks the variables the schema can't express. */ -]]
[[- define "forgejo.validate" -]]
[[- $v := vars . -]]
[[- if and $v.ssh_enabled (eq $v.ssh_port $v.http_port) -]]
[[- fail "ssh_port must differ from http_port" -]]
[[- end -]]
[[- end -]]

[[- /* region, namespace, datacenters, node_pool and the extra constraints of a job. */ -]]
[[- define "forgejo.location" -]]
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

[[- /* The keys of Forgejo as files below secrets/, owned by the container user
(the client renders them; app.ini only names the files: SECRET_KEY_URI, ...). */ -]]
[[- define "forgejo.keys" -]]
[[- $v := vars . ]]
[[- range $item := list "secret_key" "internal_token" "jwt_secret" "lfs_jwt_secret" ]]

      template {
        data        = "{{ with nomadSecret \"[[ $v.keys_secret_path ]]\" }}{{ .[[ $item ]] }}{{ end }}"
        destination = "secrets/[[ $item ]]"
        uid         = [[ $v.uid ]]
        gid         = [[ $v.gid ]]
        perms       = "0400"
        change_mode = "restart"
      }
[[- end ]]
[[- end -]]

[[- /* The S3 credentials (AWS_* variables, read by the credential chain of
Forgejo's S3 client) and the endpoint, from the catalog or storage_endpoint. */ -]]
[[- define "forgejo.storage" -]]
[[- $v := vars . ]]

      # The S3 credentials, from the built-in secret store. Forgejo's S3 client
      # reads them from the environment when app.ini has no keys.
      secret "storage" {
        path = [[ $v.storage_secret_path | quote ]]

        env {
          AWS_ACCESS_KEY_ID     = "access_key"
          AWS_SECRET_ACCESS_KEY = "secret_key"
        }
      }

      # The S3 endpoint: [[ if ne $v.storage_endpoint "" ]]storage_endpoint[[ else ]]the first instance of the service [[ $v.storage_service ]] in the native catalog[[ end ]].
      template {
        destination = "secrets/storage.env"
        env         = true
        change_mode = "restart"
        data        = <<-EOF
[[- if ne $v.storage_endpoint "" ]]
          FORGEJO__storage__MINIO_ENDPOINT=[[ $v.storage_endpoint ]]
          S3_ENDPOINT=[[ $v.storage_endpoint ]]
[[- else ]]
          {{- range $i, $s := nomadService "[[ $v.storage_service ]]" }}{{ if eq $i 0 }}
          FORGEJO__storage__MINIO_ENDPOINT={{ $s.Address }}:{{ $s.Port }}
          S3_ENDPOINT={{ $s.Address }}:{{ $s.Port }}
          {{- end }}{{ end }}
[[- end ]]
        EOF
      }
[[- end -]]
