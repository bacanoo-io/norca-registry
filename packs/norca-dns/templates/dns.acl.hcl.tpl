[[- /*
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
*/ -]]
[[- $v := vars . ]]
[[- $tokens := $v.zone_token_namespace ]][[ if eq $tokens "" ]][[ $tokens = $v.namespace ]][[ end ]]
[[- if $v.acl_policy_enabled ]]
policy [[ printf "%s" $v.job_name | quote ]] {
  description = "Permissions of norca-dns (bound to its job)"
  rules       = <<EOT
# The records are namespaced: the operator reads them in every namespace,
# writes their status and events, and keeps its finalizer on them. It reads
# the metadata of the namespaces (their allow lists), the load balancers a
# record takes its addresses from, and the DNS zones norca-provider
# registers (cluster scoped).
namespace "*" {
  capabilities = ["read-job"]

  object "norca.io/DNSRecord" {
    capabilities = ["read", "write-status", "write-events", "manage-finalizers"]
  }

  object "norca.io/LoadBalancer" {
    capabilities = ["read"]
  }

  object "norca.io/DNSZone" {
    capabilities = ["read"]
  }
}

# The tokens of the DNS zones. A block of a namespace by name takes the place
# of the "*" block for that namespace, so it names a capability of its own:
# without one the operator could not read the metadata of this namespace
# (its allow list), and no record of it would be written. Any capability
# lets the namespace be read; list-jobs is the narrowest.
namespace "[[ $tokens ]]" {
  capabilities = ["list-jobs"]

  variables {
    path [[ $v.zone_token_path | quote ]] {
      capabilities = ["read"]
    }
  }
}
EOT

  job_acl {
    namespace = [[ $v.namespace | quote ]]
    job_id    = [[ $v.job_name | quote ]]
  }
}
[[- end ]]
