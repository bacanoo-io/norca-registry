[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $ns := $v.namespace ]][[ if eq $ns "" ]][[ $ns = "<namespace of the release>" ]][[ end ]]
RustFS "[[ $job ]]" ([[ if eq $v.mode "distributed" ]]distributed, [[ len $v.nodes ]] servers[[ else ]]single server[[ end ]]) in namespace [[ $ns ]]: S3 API on port [[ $v.s3_port ]][[ if $v.console_enabled ]], console on port [[ $v.console_port ]][[ end ]].

The root credentials come from the secret [[ $v.secret_path ]] (items access_key, secret_key):
  norca secret put[[ if ne $v.namespace "" ]] -namespace [[ $v.namespace ]][[ end ]] [[ $v.secret_path ]] access_key=<access key> secret_key=-

Checks:
  norca job status[[ if ne $v.namespace "" ]] -namespace [[ $v.namespace ]][[ end ]] [[ $job ]]
  norca service info[[ if ne $v.namespace "" ]] -namespace [[ $v.namespace ]][[ end ]] -verbose [[ $job ]]
[[- if $v.buckets ]]

The poststart task create-buckets creates: [[ join ", " $v.buckets ]].
[[- else ]]

Create the backup bucket (S3 CreateBucket, signed by curl 7.75 or newer):
  curl --aws-sigv4 "aws:amz:[[ $v.s3_region ]]:s3" --user "<access key>:<secret key>" \
    -X PUT http://<node address>:[[ $v.s3_port ]]/norca-backup
[[- end ]]

Backup destination in the server configuration of the region it backs up:
  backup {
    destination "rustfs" {
      type             = "s3"
      endpoint         = "http://<node address>:[[ $v.s3_port ]]"
      bucket           = "norca-backup"
      prefix           = "norca/${region}"
      region           = "[[ $v.s3_region ]]"
      force_path_style = true
      credentials_file = "/etc/norca.d/backup-credentials"
    }
  }
