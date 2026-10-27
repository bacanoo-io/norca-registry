[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $job := $v.job_name ]][[ if eq $job "" ]][[ $job = (meta "pack.name" .) ]][[ end ]]
[[- $ns := $v.namespace ]][[ if eq $ns "" ]][[ $ns = "default" ]][[ end ]]
[[- if and $v.acl_policy_enabled $v.bootstrap_enabled ]]
policy [[ $job | quote ]] {
  description = "Tasks of the OpenObserve job [[ $job ]] (openobserve pack): ingest credentials"
  rules       = <<EOT
namespace "[[ $ns ]]" {
  # The bootstrap task stores the token of the ingest service account.
  secret "[[ $v.ingest_secret_path ]]" {
    capabilities = ["read-secret", "write-secret"]
  }
}
EOT

  job_acl {
    namespace = [[ $ns | quote ]]
    job_id    = [[ $job | quote ]]
  }
}
[[- end ]]
